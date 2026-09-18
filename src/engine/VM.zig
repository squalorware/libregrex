const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");

const AST = @import("./syntax.zig");
const Bytecode = @import("./bytecode.zig");
const utils = @import("./utils.zig");

const testing = std.testing;

const Instruction = Bytecode.Instruction;
const RegrexError = types.errors.ErrorSet;
const Match = types.Match;
const T_DestructorCallback = types.meta.T_DestructorCallback;
const CurrentRuneMatcher = utils.CurrentRuneMatcher;
const matchRune = utils.matchRune;

/// Represents a snapshot of alternative VM state produced by `Split` instruction
///
/// Used by VM to try backtracking if current execution failed - `Frame` is loaded from the `Stack`
const Frame = struct {
    /// Program counter - keeps track of executed `Instruction`s
    pc: usize,
    /// Position to which VM should backtrack to and try resuming from
    pos: usize,
    /// Snapshot of capture slots at the time the alternative path was saved.
    captures: []?usize,

    pub fn deinit(self: *Frame, alloc: std.mem.Allocator) void {
        alloc.free(self.captures);
        self.* = undefined;
    }
};

fn freeCapturesCallback(alloc: std.mem.Allocator, ptr: *Frame) void {
    ptr.deinit(alloc);
}

const Stack = types.T_ManagedArrayList(Frame, freeCapturesCallback);

/// Current execution context
///
/// Contains snapshot of the position in the input
pub const ExecutionContext = struct {
    input: []const u8,
    pos: usize,
};

fn cloneCaptures(alloc: std.mem.Allocator, captures: []const ?usize) RegrexError![]?usize {
    const clone = alloc.dupe(?usize, captures) catch {
        return RegrexError.MemoryError;
    };
    return clone;
}

/// Attempts to backtrack to the alternative state saved to Stack and restore execution from it
fn hasBacktracked(
    alloc: std.mem.Allocator,
    stack: *Stack,
    pc: *usize,
    pos: *usize,
    captures: *[]?usize,
) bool {
    const frame = stack.pop() orelse return false;
    alloc.free(captures.*);
    pc.* = frame.pc;
    pos.* = frame.pos;
    captures.* = frame.captures;
    return true;
}

/// Checks if backtracking succeded, aborts execution and cleans up context otherwise
fn hasRestoredState(
    alloc: std.mem.Allocator,
    stack: *Stack,
    pc: *usize,
    pos: *usize,
    captures: *[]?usize,
) bool {
    if (hasBacktracked(alloc, stack, pc, pos, captures)) {
        return true;
    }
    alloc.free(captures.*);
    return false;
}

/// Executes instructions in the bytecode buffer `prog` against the input starting from `start_pos`
pub fn execAt(
    allocator: std.mem.Allocator,
    input: []const u8,
    start_pos: usize,
    group_count: usize,
    prog: []const Instruction,
) RegrexError!?Match {
    const capture_slots = (group_count + 1) * 2;
    var captures = allocator.alloc(?usize, capture_slots) catch {
        return RegrexError.MemoryError;
    };
    errdefer allocator.free(captures);

    for (captures) |*slot| {
        slot.* = null;
    }

    var stack = try Stack.init(allocator, null);
    defer stack.deinit();

    // Initialize the program execution counter
    var pc: usize = 0;
    var pos: usize = start_pos;
    // Execution loop
    while (true) {
        if (pc >= prog.len) {
            if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) continue;
            return null;
        }

        const inst = prog[pc];
        switch (inst) {
            .Rune => |matcher| {
                if (try utils.runeMatched(input, &pos, .{ .literal = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Any => |matcher| {
                if (try utils.runeMatched(input, &pos, .{ .any = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Class => |matcher| {
                if (try utils.runeMatched(input, &pos, .{ .char_class = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .AssertStart => |matcher| {
                if (try utils.anchorMatched(inst, input, pos, matcher.multiline)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .AssertEnd => |matcher| {
                if (try utils.anchorMatched(inst, input, pos, matcher.multiline)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Assert => |assert| {
                if (try utils.assertMatched(input, pos, assert)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Save => |slot| {
                if (slot >= captures.len) {
                    if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                        continue;
                    }
                    return null;
                }
                captures[slot] = pos;
                pc += 1;
            },
            .Hold => return RegrexError.UnexpectedInstruction,
            // Branch execution; execute `left` branch and store `right` branch to backtracking stack
            .Split => |split| {
                const alt_captures = try cloneCaptures(allocator, captures);

                stack.append(.{
                    .pc = split.second,
                    .pos = pos,
                    .captures = alt_captures,
                }) catch {
                    return RegrexError.MemoryError;
                };
                // Resume execution from the program counter of the "left" `Frame`
                pc = split.first;
            },
            // Unconditional jump to instruction at specified index
            .Jump => |target| {
                pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try Match.init(
                    allocator,
                    group_count,
                    input,
                    captures,
                );
                allocator.free(captures);
                return result;
            },
        }
    }
}

test "execAt() should produce a Match from given position" {
    const allocator = testing.allocator;
    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .Rune = .{ .value = '4' } },
        .{ .Rune = .{ .value = '2' } },
        .{ .Rune = .{ .value = '0' } },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        "lol 420 kek",
        4,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("420", try result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "execAt() should handle capture slots" {
    const allocator = testing.allocator;
    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .Save = 2 },
        .{ .Rune = .{ .value = '4' } },
        .{ .Rune = .{ .value = '2' } },
        .{ .Rune = .{ .value = '0' } },
        .{ .Save = 3 },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        "420",
        0,
        1,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("420", try result.full());

    const expected_group = try result.group(1);
    try testing.expectEqualStrings("420", expected_group);
}

test "execAt() should consume a complete multibyte Unicode Rune" {
    const allocator = testing.allocator;

    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .Rune = .{ .value = 'Ї' } },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        "abcЇdef",
        3,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqual(
        @as(usize, 3),
        try result.start(0),
    );

    try testing.expectEqual(
        @as(usize, 5),
        try result.end(0),
    );
}

test "execAt() should correctly handle an anchored lowercase character class repeat" {
    const allocator = testing.allocator;
    const ranges = [_]AST.RuneRange{
        .{ .start = 'a', .end = 'z' },
    };
    const chars = [_]u21{};
    const lowercase_class: AST.CharClass = .{
        .ranges = ranges[0..],
        .chars = chars[0..],
    };
    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .AssertStart = .{} },
        .{
            .Split = .{
                .first = 3,
                .second = 5,
            },
        },
        .{
            .Class = .{
                .class = lowercase_class,
            },
        },
        .{ .Jump = 2 },
        .{ .AssertEnd = .{} },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        allocator,
        "abc",
        0,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("abc", try result.full());

    const no_match = try execAt(
        allocator,
        "abc123",
        0,
        0,
        prog[0..],
    );
    try testing.expect(no_match == null);
}
