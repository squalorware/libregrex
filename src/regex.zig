const std = @import("std");
const Instruction = @import("./compiler/icr.zig").Instruction;

pub const Regex = @This();

alloc: std.mem.Allocator,
compiled: []const Instruction,
group_count: usize,
raw: []const u8,

pub fn deinit(self: *Regex) void {
    for (self.compiled) |opcode| {
        switch (opcode) {
            .Class => |cls| {
                self.alloc.free(cls.ranges);
                self.alloc.free(cls.chars);
            },
            else => {},
        }
    }

    self.alloc.free(self.compiled);
}
