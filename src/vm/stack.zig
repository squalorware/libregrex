const std = @import("std");
const types = @import("types");
const ErrorSet = types.errors.ErrorSet;

pub const StackFrame = struct {
    pc: usize,
    pos: usize,
    slots: []?usize,

    pub fn deinit(self: *StackFrame, alloc: std.mem.Allocator) void {
        alloc.free(self.slots);
        self.* = undefined;
    }
};

fn releaseFrameCallback(alloc: std.mem.Allocator, ptr: *StackFrame) void {
    ptr.deinit(alloc);
}

pub const CallStack = types.T_ManagedArrayList(StackFrame, releaseFrameCallback);

pub const ExecutionContext = struct {
    call_stack: CallStack,
    pc: usize = 0,
    pos: usize = 0,
    slots: []?usize,

    pub fn init(allocator: std.mem.Allocator, pos: usize, captures_count: usize) ErrorSet!ExecutionContext {
        const slots_count = (captures_count + 1) * 2;

        const slots = allocator.alloc(?usize, slots_count) catch {
            return ErrorSet.MemoryError;
        };
        errdefer allocator.free(slots);

        for (slots) |*slot| slot.* = null;

        return .{
            .call_stack = try CallStack.init(allocator, null),
            .pos = pos,
            .slots = slots,
        };
    }

    pub fn deinit(self: *ExecutionContext, alloc: std.mem.Allocator) void {
        self.call_stack.deinit(alloc);
        alloc.free(self.slots);

        self.* = undefined;
    }

    pub fn push(self: *ExecutionContext, alloc: std.mem.Allocator, pc: usize, alt_pc: usize) ErrorSet!void {
        const alt_slots = alloc.dupe(?usize, self.slots) catch {
            return ErrorSet.MemoryError;
        };
        errdefer alloc.free(alt_slots);

        try self.call_stack.append(.{
            .pc = alt_pc,
            .pos = self.pos,
            .slots = alt_slots,
        });

        self.pc = pc;
    }

    pub fn backtrack(self: *ExecutionContext, alloc: std.mem.Allocator) bool {
        if (self.call_stack.pop()) |frame| {
            alloc.free(self.slots);

            self.pc = frame.pc;
            self.pos = frame.pos;
            self.slots = frame.slots;

            return true;
        }
        return false;
    }
};
