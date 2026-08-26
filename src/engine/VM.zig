const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");

const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const utils = @import("./utils.zig");

const testing = std.testing;

const Instruction = bytecode.Instruction;
const RegrexError = types.errors.ErrorSet;
const Match = types.Match;
const toMatch = types.conv.toMatch;
const CurrentRuneMatcher = utils.CurrentRuneMatcher;
const matchRune = utils.matchRune;

/// A saved alternative execution state used by the backtracking VM.
///
/// Frames are pushed to the VM stack by `Split` instructions. If the current frame fails, 
/// the VM retrieves the last saved frame from the stack
/// and resumes execution from its program counter and input position.
const Frame = struct {
    /// Keeps track of the next Instruction to execute
    pc: usize,
    /// Keeps track of the input byte offset to resume from.
    pos: usize,
    /// Snapshot of capture slots at the time the alternative path was saved.
    captures: []?usize,

    /// Releases the capture-slot snapshot owned by this Frame
    pub fn deinit(self: *Frame, alloc: std.mem.Allocator) void {
        alloc.free(self.captures);
        self.* = undefined;
    }
};

/// Backtracking VM execution stack for saving alternative execution states.
const Stack = types.ManagedDynamicBuffer(Frame, null);

/// Clones the current capture-slot state for a saved backtracking Frame.
///
/// Capture slots contain input byte offsets:
///
/// - slots 0/1: whole match start/end
/// - slots 2/3: capture group 1 start/end
/// - slots 4/5: capture group 2 start/end
/// - etc.
fn cloneCaptures(alloc: std.mem.Allocator, captures: []const ?usize) RegrexError![]?usize {
    const clone = alloc.dupe(?usize, captures) catch {
        return RegrexError.MemoryError;
    };
    return clone;
}

/// Tries to retrieve a last saved `Frame` from `Stack`
///
/// If a Frame was retrieved, updates the VM state (backtracks)
/// to resume execution from the saved program counter and input position, 
/// overwriting the current capture slots with the saved snapshot, then returns `true`.
/// 
/// Returns `false` if failed to retrieve a Frame from the Stack, for example because there are none
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

/// Checks if backtracking restored the VM state to resume execution.
/// 
/// Returns `true` if successfully retrieved and restored VM state with the Frame from the Stack.
/// 
/// Returns `false` otherwise, marking the entire execution as failed.
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

/// Executes bytecode instructions against the input string starting at `start_pos`
///
/// Returns `Match` if a match was found in the input.
/// 
/// Returns `null` if no match was found.
pub fn execAt(
    allocator: std.mem.Allocator, 
    input: []const u8, 
    start_pos: usize,
    group_count: usize,
    instructions: []const Instruction,
) RegrexError!?Match {
    const capture_slots = (group_count + 1) * 2;
    var captures = allocator.alloc(? usize, capture_slots) catch {
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
    // Bytecode instructions execution loop
    while (true) {
        if (pc >= instructions.len) {
            if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) continue;
            return null;
        }

        const inst = instructions[pc];
        switch (inst) {
            .Rune => |matcher| {
                if (try utils.runeMatched(input, &pos, .{.literal = matcher})) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Any => |matcher| {
                if (try utils.runeMatched(input, &pos, .{.any = matcher})) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .Class => |matcher| {
                if (try utils.runeMatched(input, &pos, .{.char_class = matcher})) {
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
                pc = split.first;
            },
            // Unconditional jump to instruction at specified index
            .Jump => |target| {
                pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try toMatch(
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

test "execAt() should produce a Match from given position" {
    const allocator = testing.allocator;
    const inst_list = [_]Instruction{
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
        inst_list[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", try result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "execAt() should handle capture slots" {
    const allocator = testing.allocator;
    const inst_list = [_]Instruction{
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
        inst_list[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", try result.full());

    const expected_group = try result.group(1);
    try testing.expectEqualStrings("420", expected_group);
}

test "execAt() should consume a complete multibyte Unicode Rune" {
    const allocator = testing.allocator;

    const inst_list = [_]Instruction{
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
        inst_list[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

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
    const ranges = [_]AST.RuneRange {
        .{ .start = 'a', .end = 'z' },
    };
    const chars = [_]u21 {};
    const lowercase_class: AST.CharClass = .{
        .ranges = ranges[0..],
        .chars = chars[0..],
    };
    const inst_list = [_]Instruction{
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
        inst_list[0..],
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("abc", try result.full());

    const no_match = try execAt(
        allocator,
        "abc123",
        0,
        0,
        inst_list[0..],
    );
    try testing.expect(no_match == null);
}
