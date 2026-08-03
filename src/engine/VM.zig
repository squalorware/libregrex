const std = @import("std");
const types = @import("types");
const Rune = @import("unicode").Rune;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const utils = @import("./utils.zig");
const Instruction = bytecode.Instruction;
const InstructionList = bytecode.InstructionList;
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
    fn deinit(self: *Frame, alloc: std.mem.Allocator) void {
        alloc.free(self.captures);
        self.* = undefined;
    }
};

/// Backtracking VM execution stack for saving alternative execution states.
const Stack = types.ManagedArrayList(Frame, null);

pub const Self = @This();

alloc: std.mem.Allocator,
stack: Stack,
pc: usize = 0,
pos: usize = 0,
captures: []?usize,

pub fn init(allocator: std.mem.Allocator, group_count: usize) RegrexError!Self {
    const capture_slots = (group_count + 1) * 2;
    const captures = allocator.alloc(usize, capture_slots) catch {
        return RegrexError.MemoryError;
    };
    errdefer allocator.free(captures);

    for (captures) |*slot| {
        slot.* = null;
    }

    return .{
        .alloc = allocator,
        .stack = Stack.init(allocator),
        .captures = captures,
    };
}

pub fn deinit(self: *Self) void {
    for (self.captures) |*slot| {
        slot.* = null;
    }
    self.alloc.free(self.captures);
    self.stack.deinit();
}

/// Clones a capture-slot buffer for a saved backtracking frame.
///
/// Capture slots store byte offsets. Slot `0` and slot `1` represent the whole
/// match start/end. Capturing group `N` uses slots `N * 2` and `N * 2 + 1`.
fn cloneCaptures(self: *Self) RegrexError![]?usize {
    const clone = self.alloc.dupe(?usize, self.captures) catch {
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
fn hasBacktracked(self: *Self) bool {
    const frame = self.stack.pop() orelse return false;
    self.alloc.free(self.captures);
    self.pc = frame.pc;
    self.pos = frame.pos;
    self.captures = frame.captures;
    return true;
}

/// Checks if backtracking restored the VM state to resume execution.
/// 
/// Returns `true` if successfully retrieved and restored VM state with the Frame from the Stack.
/// 
/// Returns `false` otherwise, marking the entire execution as failed.
fn hasRestoredState(self: *Self) bool {
    if (self.hasBacktracked()) {
        return true;
    }
    self.alloc.free(self.captures);
    return false;
}

/// Advances the execution to the next position 
/// 
/// Tries to match the current Unicode code point with a literal, a character class or any other.
/// 
/// If succeeds, increments current position with its byte length to start at the next UTF-8 character and returns `true`.
/// 
/// Returns `false` without changing current position if the `input` is exhausted 
/// or code point doesn't match any specified.
/// 
/// Returns `Error.InvalidUnicode` if encounters broken UTF-8 
fn advanceOne(self: *Self, input: []const u8, matcher: RuneMatcher) RegrexError!bool {
    const rune = try Rune.from(input[self.pos]);

    if (!matchRune(rune.raw(), matcher)) return false;

    self.pos += rune.len;
    return true;
}

/// Executes bytecode in the `InstructionList` against the input string starting at `start_pos`
///
/// Returns `Match` if a match was found in the input.
/// 
/// Returns `null` if no match was found.
pub fn execAt(self: *Self, input: []const u8, start_pos: usize, group_count: usize, inst_list: InstructionList) RegrexError!?Match {
    self.pos = start_pos;

    while (true) {
        if (self.pc >= inst_list.len()) {
            if (hasRestoredState()) continue;
            return null;
        }

        const inst = inst_list.get(self.pc);
        switch (inst) {
            .Rune => |expected| {
                const matcher = RuneMatcher{ .literal = expected };
                const fail_condition = !matchRune(expected, matcher);

                if (try AST.advanceOneRune(input, self.pos, fail_condition)) {
                    self.pc += 1;
                } else if (hasRestoredState()) {
                    continue;
                } else {
                    return null;
                }
            },
            .Any => {
                const matcher = RuneMatcher{ .any };
                const fail_condition = !matchRune(input[self.pos], matcher);

                if (try AST.advanceOneRune(input, self.pos, fail_condition)) {
                    self.pc += 1;
                } else if (hasRestoredState()) {
                    continue;
                } else {
                    return null;
                }
            },
            .CharClass => |cls| {
                const matcher = RuneMatcher{ .char_class = cls };
                const fail_condition = !matchRune(input[self.pos], matcher);

                if (try AST.advanceOneRune(input, self.pos, fail_condition)) {
                    self.pc += 1;
                } else if (hasRestoredState()) {
                    continue;
                } else {
                    return null;
                }
            },
            .AssertStart => {
                if (self.pos == 0) {
                    self.pc += 1;
                    continue;
                }
                if (hasRestoredState()) {
                    continue;
                }
                return null;
            },
            .AssertEnd => {
                if (self.pos == input.len) {
                    self.pc += 1;
                    continue;
                }
                if (hasRestoredState()) {
                    continue;
                }
                return null;
            },
            .Save => |slot| {
                if (slot >= self.captures.len) {
                    if (hasRestoredState()) {
                        continue;
                    }
                    return null;     
                }
                self.captures[slot] = self.pos;
                self.pc += 1;
            },
            // Branch execution; execute `left` branch and store `right` branch to backtracking stack
            .Split => |split| {
                const alt_captures = try cloneCaptures(self.alloc, self.captures);

                self.stack.append(self.alloc, .{
                    .pc = split.second,
                    .pos = self.pos,
                    .captures = alt_captures,
                }) catch {
                    return RegrexError.MemoryError;
                };
                self.pc = split.first;
            },
            // Unconditional jump to instruction at specified index
            .Jump => |target| {
                self.pc = target;
            },
            // Terminal instruction
            .Match => {
                const result = try toMatch(
                    self.alloc,
                    input,
                    group_count,
                    self.captures,
                );
                self.alloc.free(self.captures);
                return result;
            },
        }
    }
}
