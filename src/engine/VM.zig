const std = @import("std");
const types = @import("types");
const Rune = @import("unicode").Rune;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const Instruction = bytecode.Instruction;
const InstructionList = bytecode.InstructionList;
const RegrexError = types.Error;
const Match = types.Match;
const toMatch = types.conv.toMatch;

const RuneMatcher = union(enum) {
    any,
    literal: u21,
    char_class: AST.CharClass,
};

fn isInClass(rune: u21, cls: AST.CharClass) bool {
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

fn matchRune(rune: u21, matcher: RuneMatcher) bool {
    switch (matcher) {
        .any => return true,
        .literal => |lit| return rune == lit,
        .char_class => |cls| return isInClass(rune, cls),
    }
}

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
instructions: InstructionList,
pc: usize = 0,
pos: usize = 0,
captures: []?usize,

pub fn init(allocator: std.mem.Allocator, inst_list: *InstructionList, group_count: usize) RegrexError!Self {
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
        .instructions = try inst_list.clone(),
        .captures = captures,
    };
}

pub fn deinit(self: *Self) void {
    for (self.captures) |*slot| {
        slot.* = null;
    }
    self.alloc.free(self.captures);
    self.instructions.deinit();
    self.stack.deinit();
}

fn cloneCaptures(self: *Self) RegrexError![]?usize {
    const clone = self.alloc.dupe(?usize, self.captures) catch {
        return RegrexError.MemoryError;
    };
    return clone;
}

fn tryRestoreFromStack(self: *Self) bool {
    const frame = self.stack.pop() orelse return false;
    self.alloc.free(self.captures);
    self.pc = frame.pc;
    self.pos = frame.pos;
    self.captures = frame.captures;
    return true;
}

fn frameRecovered(self: *Self) bool {
    if (self.tryRestoreFromStack()) {
        return true;
    }
    self.alloc.free(self.captures);
    return false;
}

fn advanceOne(self: *Self, input: []const u8, matcher: RuneMatcher) RegrexError!bool {
    const rune = try Rune.from(input[self.pos]);

    if (!matchRune(rune, matcher)) return false;

    self.pos += rune.len();
    return true;
}

pub fn execAt(self: *Self, input: []const u8, group_count: usize, start_pos: usize) RegrexError!?Match {
    self.pos = start_pos;

    while (true) {
        if (self.pc >= self.instructions.len()) {
            if (frameRecovered()) continue;
            return null;
        }

        const inst = self.instructions.get(self.pc);
        switch (inst) {
            .Rune => |expected| {
                if (try self.advanceOne(input, .{ .literal = expected })) {
                    self.pc += 1;
                } else if (frameRecovered()) {
                    continue;
                } else {
                    return null;
                }
            },
            .Any => {
                if (try self.advanceOne(input, .any)) {
                    self.pc += 1;
                } else if (frameRecovered()) {
                    continue;
                } else {
                    return null;
                }
            },
            .CharClass => |cls| {
                if (try self.advanceOne(input, .{ .char_class = cls })) {
                    self.pc += 1;
                } else if (frameRecovered()) {
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
                if (frameRecovered()) {
                    continue;
                }
                return null;
            },
            .AssertEnd => {
                if (self.pos == input.len) {
                    self.pc += 1;
                    continue;
                }
                if (frameRecovered()) {
                    continue;
                }
                return null;
            },
            .Save => |slot| {
                if (slot >= self.captures.len) {
                    if (frameRecovered()) {
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
