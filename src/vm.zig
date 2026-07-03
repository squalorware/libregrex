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
const RegrexError = @import("./common/errors.zig").RegrexError;
const Instruction = @import("./core/icr.zig").Instruction;
const matchMod = @import("./match.zig");
const types = @import("./common/types.zig");
const utils = @import("./common/utils.zig");

const DecodedRune = types.DecodedRune;
const Group = types.Group;
const Match = matchMod.Match;
const MatchArray = matchMod.MatchArray;
const Rune = types.Rune;

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
) RegrexError![]?usize {
    const cloned = alloc.dupe(?usize, captures) catch {
        return RegrexError.MemoryError;
    };
    return cloned;
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
) RegrexError!bool {
    const decoded = try utils.decodeRuneAt(input, pos.*) orelse {
        return false;
    };
    if (!runeMatches(decoded.rune, matcher)) {
        return false;
    }
    pos.* += decoded.len;
    return true;
}

/// Lazy iterator over non-overlapping matches in an input string.
///
/// `FindIterator` borrows compiled bytecode and the input buffer. It does not
/// precompute or store all matches. Each call to `next()` resumes scanning from
/// the current byte position and runs the VM only until the next match is found.
pub const FindIterator = struct {
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8,
    pos: usize = 0,
    done: bool = false,

    /// Initializes an iterator starting at byte offset `0`
    pub fn init(
        alloc: std.mem.Allocator,
        bytecode: []const Instruction,
        group_count: usize,
        input: []const u8
    ) FindIterator {
        return .{
            .alloc = alloc,
            .bytecode = bytecode,
            .group_count = group_count,
            .input = input,
            .pos = 0,
            .done = false,
        };
    }

    /// Resume scanning from the iterator's current byte position.
    /// 
    /// Returns a non-overlappping `Match` if one is found; then the iterator
    /// advances to the end of this match. If zero-length Match is encountered, 
    /// the iterator advances by one UTF-8 code point to avoid infinite loop
    /// 
    /// Returns 
    /// - `Error.MemoryError` if allocation failed
    /// - `Error.InvalidUnicode` 
    ///     (propagated by `VM.execAt` or encountered during lookup)
    pub fn next(self: *FindIterator) RegrexError!?Match {
        if (self.done) return null;

        while (self.pos <= self.input.len) {
            if (try execAt(
                self.alloc, 
                self.bytecode, 
                self.group_count, 
                self.input, 
                self.pos
            )) |m| {
                const start = try m.start(0);
                const end = try m.end(0);

                if (end > start) {
                    // Non-empty match; mark as finished and resume scanning
                    self.pos = end;
                } else {
                    // Zero-length match. Advance one UTF-8 code point to avoid infinite loop
                    const decoded = try utils.decodeRuneAt(self.input, self.pos);

                    if (decoded == null) {
                        // Empty match. Nowhere to advance;
                        self.done = true;
                    } else {
                        self.pos += decoded.?.len;
                    }
                }
                // Next match found; return it
                return m;
            }
            // No match at this offset. Move to the next UTF-8 code point and try again. 
            const decoded = try utils.decodeRuneAt(self.input, self.pos);

            if (decoded == null) {
                self.done = true;
                return null;
            }
            self.pos += decoded.?.len;
        }
        self.done = true;
        return null;
    }

    pub fn deinit(self: *FindIterator) void {
        self.* = undefined;
    }
};

/// Executes bytecode instructions.
/// 
/// The core function used by high-level API.
/// Starts at bytecode instruction `0` and input byte position `start_pos`.
/// 
/// Owns temporary capture slots and backtracking frames while executing.
/// Returns `Match` on success.
/// 
/// Returns `null` and releases temporary VM state on failure.
/// 
/// Returns 
/// - `Error.MemoryError` if backtracking stack or captures buffer allocation failed;
/// - `Error.InvalidUnicode` if tried to consume a broken UTF-8 code point;
pub fn execAt(
    allocator: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8,
    start_pos: usize,
) RegrexError!?Match {
    const capture_slots = (group_count + 1) * 2;

    var captures = allocator.alloc(?usize, capture_slots) catch {
        return RegrexError.MemoryError;
    };
    errdefer allocator.free(captures);

    for (captures) |*slot| {
        slot.* = null;
    }

    // Initialize the backtracking VM 'stack' (Frame buffer)
    var stack = std.ArrayList(Frame).empty;
    // Free the backtracking frame state buffer
    defer {
        for (stack.items) |*frame| {
            frame.deinit(allocator);
        }
        stack.deinit(allocator);
    }

    // Initialize the program execution counter
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
            // Branch execution; execute `left` branch and store `right` branch to backtracking stack
            .Split => |split| {
                const alt_captures = try cloneCaptures(allocator, captures);

                stack.append(allocator, .{
                    .pc = split.second,
                    .pos = pos,
                    .captures = alt_captures,
                }) catch {
                    return RegrexError.MemoryError;
                };
                pc = split.first;
            },
            // Unconditional jump to instruction at specified index
            .Jump => |target| {
                pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try matchMod.toMatch(
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
/// Returns 
/// - `Error.MemoryError` if allocation failed
/// - `Error.InvalidUnicode` (propagated by `VM.execAt`)
pub fn match(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) RegrexError!?Match {
    return execAt(alloc, bytecode, group_count, input, 0);
}

/// Executes the bytecode-compiled pattern to search for the first position 
/// in the `input` where a `Match` can be produced.
/// 
/// Returns the first `Match` produced at any position 
/// 
/// Returns `null` if no `Match` can be produced anywhere in `input`
/// 
/// Returns 
/// - `Error.MemoryError` if allocation failed
/// - `Error.InvalidUnicode` (propagated by `VM.execAt` or encountered during lookup)
pub fn search(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) RegrexError!?Match {
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

/// Creates a lazy iterator over all non-overlapping matches in `input` string.
/// 
/// Does not scan the input immediately - initializes a `FindIterator` instead.
/// Matching is performed one item at a time when `FindIterator.next` is called.
pub fn findIter(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8,
) FindIterator {
    return FindIterator.init(
        alloc, 
        bytecode, 
        group_count, 
        input
    );
}

/// Executes the bytecode-compiled pattern to search for 
/// all non-overlapping matches in `input` string.
/// 
/// An 'eager' counterpart to `findIter`. Consumes a `FindIterator`
/// until it is exhausted and stores every returned match in an owned slice
/// (must be released, e.g. with `Match.free`)
/// 
/// Returns an allocator-owned slice of `Match` objects.
/// 
/// Returns 
/// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
/// - `Error.InvalidUnicode` (propagated by `VM.execAt` or encountered during lookup)
pub fn findAll(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8
) RegrexError!MatchArray {
    var iter = findIter(
        alloc,
        bytecode,
        group_count,
        input,
    );
    defer iter.deinit();

    var matches = MatchArray.init(alloc);
    errdefer matches.deinit();

    while (try iter.next()) |m| try matches.append(m);

    return matches;
}

/// Executes the bytecode-compiled pattern to retrieve all of the matches 
/// in the `input` string and return its copy with matches  replaced by `repl`.
/// 
/// The replacement is literal. Current implementation does not support 
/// expanding capture group references like `\1` or `$1` and flags like 'ignore case'.
/// 
/// `count` argument controls the number of occurences to replace. 
/// - If `count = 0`, replaces all of the occurences;
/// - If `count > 0` replaces number of the occurences specified
/// - If `count` is bigger than the actual occurences count, replaces all and safely ignores rest
/// 
/// Returns an allocator-owned copy of the input string (must be freed manually with `alloc.free`).
/// 
/// Returns 
/// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
/// - `Error.InvalidUnicode` (propagated by `VM.execAt` or encountered during lookup)
pub fn sub(
    alloc: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    repl: []const u8,
    input: []const u8,
    count: usize,
) RegrexError![]u8 {
    // Initialize a slice to store the output string
    var out_buf = std.ArrayList(u8).empty;
    errdefer out_buf.deinit(alloc);

    var scan_pos: usize = 0; // byte offset to scan for next match
    var copy_pos: usize = 0; // start of next unmatched input segment to copy
    var replacements: usize = 0; // performed replacements count

    while (scan_pos <= input.len) {
        // Safely ignore if count is greater than the actual occurences number
        if (count != 0 and replacements >= count) {
            break;
        }

        // Try matching at current offset
        if (try execAt(alloc, bytecode, group_count, input, scan_pos)) |m| {
            var match_result = m;
            defer match_result.deinit(alloc);

            const start = try match_result.start(0);
            const end = try match_result.end(0);

            // Copy everything from last emitted position to start 
            out_buf.appendSlice(alloc, input[copy_pos..start]) catch {
                return RegrexError.MemoryError;
            };
            // Copy replacement instead of match
            out_buf.appendSlice(alloc, repl) catch {
                return RegrexError.MemoryError;
            };

            replacements += 1;

            if (end > start) {
                // Non-empty match; mark finished and resume scanning
                scan_pos = end;
                copy_pos = end;
            } else {
                // Zero-length match. Advance one UTF-8 code point to avoid infinite loop
                const decoded = try utils.decodeRuneAt(input, scan_pos);
                if (decoded == null) {
                    // Empty match. Replace and finish
                    copy_pos = scan_pos;
                    break;
                }

                const next_pos = scan_pos + decoded.?.len;
                // Preserve original code point after zero-length replacement 
                // to avoid overwriting/deleting input while advancing
                out_buf.appendSlice(alloc, input[scan_pos..next_pos]) catch {
                    return RegrexError.MemoryError;
                };

                scan_pos = next_pos;
                copy_pos = next_pos;
            }
            continue;
        }
        // No match at this offset. Move to the next UTF-8 code point and try again.
        // `copy_pos` not changed because this input was not emitted yet; copy it 
        // if a later match is found or at the end of the function
        const decoded = try utils.decodeRuneAt(input, scan_pos);
        if (decoded == null) break;

        scan_pos += decoded.?.len;
    }
    // Copy unmatched tail of the input into buffer and transfer ownership over it to caller
    out_buf.appendSlice(alloc, input[copy_pos..]) catch {
        return RegrexError.MemoryError;
    };
    const out = out_buf.toOwnedSlice(alloc) catch {
        return RegrexError.MemoryError;
    };
    return out;
}

const testing = std.testing;

test "VM.execAt() should produce a Match from the initial position (0)" {
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

    try testing.expectEqualStrings("420", result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "VM.match() should return the first match at the start of input string" {
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

    try testing.expectEqualStrings("420", result.full());

    const no_match = try match(
        allocator,
        bytecode[0..],
        0,
        "lol 420 kek",
    );
    try testing.expect(no_match == null);
}

test "VM.search() should return the first match encountered" {
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

    try testing.expectEqualStrings("420", result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "VM.findIter() should perform lazy iteration over non-overlapping matches" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };
    var iter = findIter(
        allocator,
        bytecode[0..],
        0,
        "420 lol 420 kek",
    );
    defer iter.deinit();

    var first = (try iter.next()) orelse {
        try testing.expect(false);
        return;
    };
    defer first.deinit(allocator);
    try testing.expectEqualStrings("420", first.full());
    try testing.expectEqual(@as(usize, 0), try first.start(0));
    try testing.expectEqual(@as(usize, 3), try first.end(0));

    var second = (try iter.next()) orelse {
        try testing.expect(false);
        return;
    };
    defer second.deinit(allocator);
    try testing.expectEqualStrings("420", second.full());
    try testing.expectEqual(@as(usize, 8),try second.start(0));
    try testing.expectEqual(@as(usize, 11), try second.end(0));

    const third = try iter.next();
    try testing.expect(third == null);
}

test "VM.findIter() should return null if next iteration yields no match" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };
    var iter = findIter(
        allocator,
        bytecode[0..],
        0,
        "lol kek",
    );
    defer iter.deinit();

    const result = try iter.next();
    try testing.expect(result == null);    
}

test "VM.findAll() should return all discovered non-overlapping matches" {
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

    var results = try findAll(
        allocator, 
        bytecode[0..], 
        0, 
        "67 lol six seven 67 kek 420"
    );
    defer results.deinit();

    try testing.expectEqual(@as(usize, 2), results.len());

    const matches = results.items();
    for (expected_matches, 0..) |expected, i| {
        try testing.expectEqualStrings("67", matches[i].full());
        try testing.expectEqual(expected.start, matches[i].start(0));
        try testing.expectEqual(expected.end,matches[i].end(0));
    }
}

test "VM.execAt() should handle capture slots" {
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

    try testing.expectEqualStrings("420", result.full());

    const expected_group = try result.group(1);
    try testing.expectEqualStrings("420", expected_group);
}

test "VM.execAt() should correctly handle an anchored lowercase character class repeat" {
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

    try testing.expectEqualStrings("abc", result.full());

    const no_match = try execAt(
        allocator,
        bytecode[0..],
        0,
        "abc123",
        0
    );
    try testing.expect(no_match == null);
}

test "VM.sub() should replace all matched occurences with provided string" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };

    const result = try sub(
        allocator,
        bytecode[0..],
        0,
        "67",
        "lol 420 kek 420",
        0,
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol 67 kek 67", result);
}

test "VM.sub() should replace only specified number of occurences with a provided string" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };

    const result = try sub(
        allocator,
        bytecode[0..],
        0,
        "67",
        "lol 420 kek 420",
        1,
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol 67 kek 420", result);
}

test "VM.sub() should replace all occurences and safely ignore rest if count is greater than actual occurences count" {
    const allocator = testing.allocator;
    const bytecode = [_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    };

    const result = try sub(
        allocator,
        bytecode[0..],
        0,
        "67",
        "lol 420 kek 420",
        67,
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol 67 kek 67", result);
}
