//! Backtracking virtual machine for compiled regular-expression bytecode.
//! 
//! The VM executes the instruction stream emitted by the compiler. 
//! Backtracks by `Split` instructions pushing alternative execution states 
//! onto an explicit stack, and failed paths restore the most recent saved state.
//! 
//! Input is stored and sliced as UTF-8 byte slices, but character-consuming
//! instructions operate on decoded Unicode scalar values. Match spans
//! are byte offsets so that they can be used directly with Zig slice syntax.
const std = @import("std");
const AST = @import("./core/ast.zig");
const Error = @import("./common/errors.zig").Error;
const Instruction = @import("./core/icr.zig").Instruction;
const Match = @import("./Match.zig");
const types = @import("./common/types.zig");
const utils = @import("./common/utils.zig");

const DecodedRune = types.DecodedRune;
const Rune = types.Rune;
const Span = types.Span;
const VmError = Error || std.mem.Allocator.Error;

/// A saved alternative execution state instance used by the backtracking VM.
///
/// Frames are pushed by `Split` instructions. If the current frame fails, 
/// the VM restores the most recent Frame and continues from that saved
/// program counter, input byte position, and capture-slot snapshot.
const Frame = struct {
    /// Bytecode instruction pointer to resume from
    pc: usize,
    /// Input byte offset to resume from.
    pos: usize,
    /// Snapshot of capture slots at the time the alternative path was saved.
    captures: []?usize,

    /// Releases the capture-slot snapshot owned by this Frame
    fn deinit(self: *Frame, alloc: std.mem.Allocator) void {
        alloc.free(self.captures);
        self.* = undefined;
    }
};

/// Represents a rule by which a Rune-consuming Instruction should test it.
/// 
/// This lets `.Rune`, `.Any`, and `.Class` share the same consume/decode path
/// while preserving their distinct matching semantics.
const RuneMatcher = union(enum) {
    any,
    exact: Rune,
    class: AST.CharClass,
};

/// Clones a capture-slot buffer for a saved backtracking frame.
///
/// Capture slots store byte offsets. Slot `0` and slot `1` represent the whole
/// match start/end. Capturing group `N` uses slots `N * 2` and `N * 2 + 1`.
fn cloneCaptures(
    alloc: std.mem.Allocator,
    captures: []const ?usize,
) VmError![]?usize {
    return try alloc.dupe(?usize, captures);
}

/// Restores the most recent backtracking Frame from `stack`.
///
/// Frees the current capture buffer and replaces it with
/// the capture snapshot owned by the restored Frame.
/// 
/// Returns `false` if no alternative Frame exists
fn restoreFromStack(
    alloc: std.mem.Allocator,
    stack: *std.ArrayList(Frame),
    captures: *[]?usize,
    pc: *usize,
    pos: *usize,
) bool {
    const frame = stack.pop() orelse return false;

    alloc.free(captures.*);

    pc.* = frame.pc;
    pos.* = frame.pos;
    captures.* = frame.captures;

    return true;
}

/// Recovers from a failed VM Frame or marks whole execution as failed.
/// 
/// Returns `true` if alternative Frame was restored
/// 
/// Returns `false` after freeing the current capture buffer
/// when the backtracking stack is exhausted
fn recoverOrFail(
    alloc: std.mem.Allocator,
    stack: *std.ArrayList(Frame),
    captures: *[]?usize,
    pc: *usize,
    pos: *usize,
) bool {
    if (restoreFromStack(alloc, stack, captures, pc, pos)) {
        return true;
    }
    alloc.free(captures.*);
    return false;
}

/// Returns whether a Rune is accepted by a CharClass
/// 
/// Character classes are represented as a set of explicit runes 
/// plus a set of inclusive rune ranges. 
/// 
/// Negated classes invert the final result
fn runeInClass(rune: Rune, cls: AST.CharClass) bool {
    var matched = false;

    for (cls.ranges) |range| {
        if (rune >= range.start and rune <= range.end) {
            matched = true;
            break;
        }
    }

    if (!matched) {
        for (cls.chars) |char| {
            if (rune == char) {
                matched = true;
                break;
            }
        }
    }
    return if (cls.negated) !matched else matched;
}

/// Returns whether Rune satisfies the provided matcher
fn runeMatches(rune: Rune, matcher: RuneMatcher) bool {
    return switch(matcher) {
        .any => true,
        .exact => |expected| rune == expected,
        .class => |cls| runeInClass(rune, cls),
    };
}

/// Consumes a UTF-8 code point from `input` at `pos`
/// 
/// Returns `true` and advances `pos` if decoded Rune satisfies the matcher.
/// 
/// Returns `false` without changing `pos` if the `input` is exhausted 
/// or Rune doesn't match
/// 
/// Returns `Error.InvalidUnicode` if encounters broken UTF-8 
fn consumeRune(
    input: []const u8,
    pos: *usize,
    matcher: RuneMatcher,
) VmError!bool {
    const decoded = try utils.decodeRuneAt(input, pos.*) orelse {
        return false;
    };
    if (!runeMatches(decoded.rune, matcher)) {
        return false;
    }
    pos.* += decoded.len;
    return true;
}

/// Executes bytecode instructions.
/// 
/// The core function used by high-level API.
/// Starts at bytecode instruction `0` and input byte position `start_pos`.
/// 
/// Owns temporary capture slots and backtracking frames while executing.
/// Returns `Match` on success.
/// 
/// Returns `null` and releases temporary VM state on failure.
pub fn execAt(
    allocator: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8,
    start_pos: usize,
) VmError!?Match {
    const capture_slots = (group_count + 1) * 2;

    var captures = try allocator.alloc(?usize, capture_slots);
    errdefer allocator.free(captures);

    for (captures) |*slot| {
        slot.* = null;
    }

    var stack = std.ArrayList(Frame).empty;
    // Free the backtracking frame state buffer
    defer {
        for (stack.items) |*frame| {
            frame.deinit(allocator);
        }
        stack.deinit(allocator);
    }

    // Initialize the program counter
    var pc: usize = 0;
    var pos: usize = start_pos;
    // Bytecode instruction execution loop
    while (true) {
        if (pc >= bytecode.len) {
            if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                continue;
            }
            return null;
        }
        const inst = bytecode[pc];
        switch (inst) {
            .Rune => |expected| {
                if (try consumeRune(input, &pos, .{ .exact = expected})) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                    continue;
                }
                return null;
            },
            .Any => {
                if (try consumeRune(input, &pos, .any)) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                    continue;
                }
                return null;                
            },
            .Class => |cls| {
                if (try consumeRune(input, &pos, .{ .class = cls})) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                    continue;
                }
                return null;
            },
            .AssertStart => {
                if (pos == 0) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                    continue;
                }
                return null;
            },
            .AssertEnd => {
                if (pos == input.len) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                    continue;
                }
                return null;
            },
            .Save => |slot| {
                if (slot >= captures.len) {
                    if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                        continue;
                    }
                    return null;     
                }
                captures[slot] = pos;
                pc += 1;
            },
            .Split => |split| {
                const alt_captures = try cloneCaptures(allocator, captures);

                try stack.append(allocator, .{
                    .pc = split.second,
                    .pos = pos,
                    .captures = alt_captures,
                });
                pc = split.first;
            },
            .Jump => |target| {
                pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try Match.toMatch(
                    allocator,
                    input,
                    group_count,
                    captures,
                );
                allocator.free(captures);
                return result;
            },
        }
    }
}

/// Executes the bytecode-compiled pattern to return the first match 
/// found starting from byte offset `0` (i.e. start of `input` string)
/// 
/// Returns `Match` if the compiled pattern succeeds at the start of `input`
/// 
/// Returns `null` if no `Match` can be produced from start of `input`
/// 
/// Returns `VmError` if memory allocation for `Match` failed or 
/// an invalid Unicode character was detected
pub fn match(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) VmError!?Match {
    return execAt(alloc, bytecode, group_count, input, 0);
}

/// Executes the bytecode-compiled pattern to search for the first position 
/// in the `input` where a `Match` can be produced.
/// 
/// Returns the first `Match` produced at any position 
/// 
/// Returns `null` if no `Match` can be produced anywhere in `input`
/// 
/// Returns `VmError` if memory allocation for `Match` failed or 
/// an invalid Unicode character was detected
pub fn search(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) VmError!?Match {
    var pos: usize = 0;

    while (pos <= input.len) {
        if (try execAt(alloc, bytecode, group_count, input, pos)) |m| {
            return m;
        }
        const decoded = try utils.decodeRuneAt(input, pos);
        
        if (decoded == null) break;

        pos += decoded.?.len;
    }
    return null;
}

/// Executes the bytecode-compiled pattern to search for 
/// all non-overlapping matches in `input` string.
/// 
/// Runs bytecode from left to right at valid Unicode boundaries.
/// After a successful non-empty match, scanning resumes at the end
/// of that match. If a zero-length Match is produced, scanning advances by one
/// UTF-8 code point to avoid an infinite loop.
/// 
/// Returns an allocator-owned slice of `Match` objects.
/// 
/// Returns `VmError` if memory allocation failed or 
/// an invalid Unicode character was detected
pub fn findAll(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) VmError![]Match {
    var matches = std.ArrayList(Match).empty;
    errdefer Match.free(alloc, matches.items);
    var pos: usize = 0;

    while (pos <= input.len) {
        if (try execAt(alloc, bytecode, group_count, input, pos)) |m| {
            const start = m.span.start;
            const end = m.span.end;

            try matches.append(alloc, m);

            if (end > start) {
                pos = end;
            } else {
                const decoded = try utils.decodeRuneAt(input, pos);

                if (decoded == null) break;

                pos += decoded.?.len;
            }
            continue;
        }
        const decoded = try utils.decodeRuneAt(input, pos);

        if (decoded == null) break;

        pos += decoded.?.len;
    }
    return try matches.toOwnedSlice(alloc);
}

const testing = std.testing;

test "Should match executing bytecode for literal from explicit start by VM.execAt" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };
    var result = (try execAt(
        allocator,
        bytecode[0..],
        0,
        "lol 420 kek",
        4,
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.str());
    try testing.expectEqual(@as(usize, 4), result.span.start);
    try testing.expectEqual(@as(usize, 7), result.span.end);
}

test "Should match only at input start by VM.match" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try match(
        allocator,
        bytecode[0..],
        0,
        "420 kek",
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.str());

    const no_match = try match(
        allocator,
        bytecode[0..],
        0,
        "lol 420 kek",
    );
    try testing.expect(no_match == null);
}

test "Should find first matching literal after beginning with VM.search" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try search(
        allocator,
        bytecode[0..],
        0,
        "lol 420 kek",
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.str());
    try testing.expectEqual(@as(usize, 4), result.span.start);
    try testing.expectEqual(@as(usize, 7), result.span.end);
}

test "Should receive all non-overlapping matches from VM.findAll" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '6' },
        .{ .Rune = '7' },
        .{ .Save = 1 },
        .Match,
    };
    const expected_matches = [_]struct {
        start: usize,
        end: usize,
    }{
        .{ .start = 0, .end = 2 },
        .{ .start = 17, .end = 19 },
    };

    const results = try findAll(
        allocator, 
        bytecode[0..], 
        0, 
        "67 lol six seven 67 kek 420"
    );
    defer Match.free(allocator, results);

    try testing.expectEqual(@as(usize, 2), results.len);

    for (expected_matches, 0..) |expected, i| {
        try testing.expectEqualStrings("67", results[i].str());
        try testing.expectEqual(expected.start, results[i].span.start);
        try testing.expectEqual(expected.end,results[i].span.end);
    }
}

test "Should handle capture group save slots by VM.execAt" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Save = 2 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 3 },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        bytecode[0..],
        1,
        "420",
        0,
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.str());

    const expected_group = result.group(1) orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("420", expected_group);
}

test "Should handle anchored lowercase character class repeat by VM.execAt" {
    const allocator = testing.allocator;
    const ranges = [_]AST.CharRange {
        .{ .start = 'a', .end = 'z' },
    };
    const chars = [_]Rune {};
    const lowercase_class: AST.CharClass = .{
        .ranges = ranges[0..],
        .chars = chars[0..],
        .negated = false,
    };
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .AssertStart,
        .{ .Split = .{ .first = 3, .second = 5 } },
        .{ .Class = lowercase_class },
        .{ .Jump = 2 },
        .AssertEnd,
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        bytecode[0..],
        0,
        "abc",
        0
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("abc", result.str());

    const no_match = try execAt(
        allocator,
        bytecode[0..],
        0,
        "abc123",
        0
    );
    try testing.expect(no_match == null);
}
