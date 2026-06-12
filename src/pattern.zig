const std = @import("std");
const Instruction = @import("./core/icr.zig").Instruction;

const CompiledPattern = struct {
    alloc: std.mem.Allocator,
    bytecode: []Instruction,
    group_count: usize,
    pattern: []const u8,
};

pub const Pattern = opaque {
    pub fn init(
        alloc: std.mem.Allocator,
        group_count: usize,
        opcodes: []Instruction,
        pattern: []const u8,
    ) !*Pattern {
        const self = try alloc.create(CompiledPattern);
        self.* = .{
            .alloc = alloc,
            .bytecode = opcodes,
            .group_count = group_count,
            .pattern = pattern,
        };
        return @ptrCast(self);
    }

    pub fn deinit(ptr: *Pattern) void {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
        const alloc = self.alloc;

        freeBytecode(alloc, self.bytecode);

        self.* = undefined;
        alloc.destroy(self);
    }

    pub fn freeBytecode(
        alloc: std.mem.Allocator, 
        bytecode: []Instruction
    ) void {
        for (bytecode) |inst| {
            switch(inst) {
                .Class => |cls| {
                    alloc.free(cls.ranges);
                    alloc.free(cls.chars);
                },
                else => {},
            }
        }

        alloc.free(bytecode);
    }

    pub fn search() void {}
    pub fn match() void {}
    pub fn findAll() void {}
};
