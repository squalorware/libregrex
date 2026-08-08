const std = @import("std");
const types = @import("types");
const Rune = @import("unicode").Rune;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const utils = @import("./utils.zig");
const Instruction = bytecode.Instruction;
const RegrexError = types.Error;
const Match = types.Match;
const toMatch = types.conv.toMatch;
const RuneMatcher = utils.RuneMatcher;
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

/// Clones a capture-slot buffer for a saved backtracking frame.
///
/// Capture slots store byte offsets. Slot `0` and slot `1` represent the whole
/// match start/end. Capturing group `N` uses slots `N * 2` and `N * 2 + 1`.
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
    // Bytecode instructions execution loop
    while (true) {
        if (pc >= instructions.len) {
            if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) continue;
            return null;
        }

        const inst = instructions[pc];
        switch (inst) {
            .Rune => |expected| {
                const matcher = RuneMatcher{ .literal = expected };
                const fail_condition = !matchRune(expected, matcher);

                if (try utils.advanceOneRune(input, &pos, fail_condition)) {
                    pc += 1;
                } else if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                } else {
                    return null;
                }
            },
            .Any => {
                const matcher = RuneMatcher{ .any = {} };
                const fail_condition = !matchRune(input[pos], matcher);

                if (try utils.advanceOneRune(input, &pos, fail_condition)) {
                    pc += 1;
                } else if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                } else {
                    return null;
                }
            },
            .Class => |cls| {
                const matcher = RuneMatcher{ .char_class = cls };
                const fail_condition = !matchRune(input[pos], matcher);

                if (try utils.advanceOneRune(input, &pos, fail_condition)) {
                    pc += 1;
                } else if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                } else {
                    return null;
                }
            },
            .AssertStart => {
                if (pos == 0) {
                    pc += 1;
                    continue;
                }
                if (hasRestoredState(allocator, &stack, &pc, &pos, &captures)) {
                    continue;
                }
                return null;
            },
            .AssertEnd => {
                if (pos == input.len) {
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
