const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");

const AST = @import("./parsing/syntax.zig");
const Bytecode = @import("./bytecode.zig");
const utils = @import("./utils.zig");

const testing = std.testing;

const Instruction = Bytecode.Instruction;
const ErrorSet = types.errors.ErrorSet;
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
    slots: []?usize,

    pub fn deinit(self: *Frame, gpa: std.mem.Allocator) void {
        gpa.free(self.slots);
        self.* = undefined;
    }
};

fn freeCapturesCallback(gpa: std.mem.Allocator, ptr: *Frame) void {
    ptr.deinit(gpa);
}

const Stack = types.T_ManagedArrayList(Frame, freeCapturesCallback);

/// Current execution context
///
/// Contains snapshot of the position in the input
pub const ExecutionContext = struct {
    input: []const u8,
    pos: usize,
};

fn cloneCaptures(gpa: std.mem.Allocator, slots: []const ?usize) ErrorSet![]?usize {
    const clone = gpa.dupe(?usize, slots) catch {
        return ErrorSet.MemoryError;
    };
    return clone;
}

/// Attempts to backtrack to the alternative state saved to Stack and restore execution from it
/// Checks if backtracking succeded, aborts execution and cleans up context otherwise
fn hasRestoredState(
    gpa: std.mem.Allocator,
    stack: *Stack,
    pc: *usize,
    pos: *usize,
    slots: *[]?usize,
) bool {
    if (stack.pop()) |frame| {
        gpa.free(slots.*);
        pc.* = frame.pc;
        pos.* = frame.pos;
        slots.* = frame.slots;
        return true;
    }
    gpa.free(slots.*);
    return false;
}

/// Executes instructions in the bytecode buffer `prog` against the input starting from `start_pos`
pub fn execAt(
    gpa: std.mem.Allocator,
    input: []const u8,
    start_pos: usize,
    captures_count: usize,
    prog: []const Instruction,
) ErrorSet!?Match {
    const reg_count = (captures_count + 1) * 2;
    var slots = gpa.alloc(?usize, reg_count) catch {
        return ErrorSet.MemoryError;
    };
    errdefer gpa.free(slots);

    for (slots) |*slot| {
        slot.* = null;
    }

    var stack = try Stack.init(gpa, null);
    defer stack.deinit();

    // Initialize the program execution counter
    var pc: usize = 0;
    var pos: usize = start_pos;
    // Execution loop
    while (true) {
        if (pc >= prog.len) {
            if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) continue;
            return null;
        }

        const inst = prog[pc];
        switch (inst) {
            .Rune => |matcher| {
                if (try utils.consumeMatchingRune(input, &pos, .{ .literal = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .Any => |matcher| {
                if (try utils.consumeMatchingRune(input, &pos, .{ .any = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .Class => |matcher| {
                if (try utils.consumeMatchingRune(input, &pos, .{ .char_class = matcher })) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .AssertStart => |matcher| {
                if (try utils.matchesAnchor(inst, input, pos, matcher.multiline)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .AssertEnd => |matcher| {
                if (try utils.matchesAnchor(inst, input, pos, matcher.multiline)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .Assert => |assert| {
                if (try utils.matchesAssertion(input, pos, assert)) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                    continue;
                }
                return null;
            },
            .Save => |slot| {
                if (slot >= slots.len) {
                    if (hasRestoredState(gpa, &stack, &pc, &pos, &slots)) {
                        continue;
                    }
                    return null;
                }
                slots[slot] = pos;
                pc += 1;
            },
            .Hold => return ErrorSet.UnexpectedInstruction,
            // Branch execution; execute `left` branch and store `right` branch to backtracking stack
            .Split => |split| {
                const alt_captures = try cloneCaptures(gpa, slots);

                stack.append(.{
                    .pc = split.right,
                    .pos = pos,
                    .slots = alt_captures,
                }) catch {
                    return ErrorSet.MemoryError;
                };
                // Resume execution from the program counter of the "left" `Frame`
                pc = split.left;
            },
            // Unconditional jump to instruction at specified index
            .Jump => |target| {
                pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try Match.init(
                    gpa,
                    captures_count,
                    input,
                    slots,
                );
                gpa.free(slots);
                return result;
            },
        }
    }
}

test "execAt() should produce a Match from given position" {
    const gpa = testing.allocator;
    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .Rune = .{ .value = '4' } },
        .{ .Rune = .{ .value = '2' } },
        .{ .Rune = .{ .value = '0' } },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        gpa,
        "lol 420 kek",
        4,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(gpa);

    try testing.expectEqualStrings("420", try result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "execAt() should handle capture slots" {
    const gpa = testing.gpa;
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
        gpa,
        "420",
        0,
        1,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(gpa);

    try testing.expectEqualStrings("420", try result.full());

    const expected_group = try result.group(1);
    try testing.expectEqualStrings("420", expected_group);
}

test "execAt() should consume a complete multibyte Unicode Rune" {
    const gpa = testing.gpa;

    const prog = [_]Instruction{
        .{ .Save = 0 },
        .{ .Rune = .{ .value = 'Ї' } },
        .{ .Save = 1 },
        .Match,
    };

    var result = (try execAt(
        gpa,
        "abcЇdef",
        3,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(gpa);

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
    const gpa = testing.allocator;
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
                .left = 3,
                .right = 5,
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
        gpa,
        "abc",
        0,
        0,
        prog[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(gpa);

    try testing.expectEqualStrings("abc", try result.full());

    const no_match = try execAt(
        gpa,
        "abc123",
        0,
        0,
        prog[0..],
    );
    try testing.expect(no_match == null);
}
