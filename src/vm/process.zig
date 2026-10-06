const std = @import("std");
const types = @import("types");
const ErrorSet = types.errors.ErrorSet;

pub const Frame = struct {
    pc: usize,
    pos: usize,
    slots: []?usize,

    pub fn deinit(self: *Frame, gpa: std.mem.Allocator) void {
        gpa.free(self.slots);
        self.* = undefined;
    }
};

fn releaseFrameCallback(gpa: std.mem.Allocator, ptr: *Frame) void {
    ptr.deinit(gpa);
}

pub const FrameBuffer = types.T_ManagedArrayList(Frame, releaseFrameCallback);

pub const Context = struct {
    stack: FrameBuffer,
    pc: usize = 0,
    pos: usize = 0,
    slots: []?usize,

    pub fn init(gpa: std.mem.Allocator, pos: usize, captures_count: usize) ErrorSet!Context {
        const slots_count = (captures_count + 1) * 2;

        const slots = gpa.alloc(?usize, slots_count) catch {
            return ErrorSet.MemoryError;
        };
        errdefer gpa.free(slots);

        for (slots) |*slot| slot.* = null;

        return .{
            .stack = try FrameBuffer.init(gpa, null),
            .pos = pos,
            .slots = slots,
        };
    }

    pub fn deinit(self: *Context, gpa: std.mem.Allocator) void {
        gpa.free(self.slots);

        self.stack.deinit();
        self.* = undefined;
    }

    pub fn inc(self: *Context, pc: usize) void {
        self.pc += pc;
    }

    pub fn acc(self: Context) usize {
        return self.pc;
    }

    pub fn push(self: *Context, gpa: std.mem.Allocator, pc: usize, alt_pc: usize) ErrorSet!void {
        const alt_slots = gpa.dupe(?usize, self.slots) catch {
            return ErrorSet.MemoryError;
        };
        errdefer gpa.free(alt_slots);

        try self.stack.append(.{
            .pc = alt_pc,
            .pos = self.pos,
            .slots = alt_slots,
        });

        self.pc = pc;
    }

    pub fn backtrack(self: *Context, gpa: std.mem.Allocator) bool {
        if (self.stack.len() == 0) {
            return false;
        }
        const frame = self.stack.pop() orelse return false;

        self.pc = frame.pc;
        self.pos = frame.pos;
        @memcpy(self.slots, frame.slots);
        // discard frame already used
        frame.deinit(gpa);

        return true;
    }
};
