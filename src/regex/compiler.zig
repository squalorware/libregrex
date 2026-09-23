const std = @import("std");
const types = @import("types");
const opcodes = @import("./opcodes.zig");
const syntax = @import("./syntax.zig");
const BytecodeBuffer = opcodes.BytecodeBuffer;
const ErrorSet = types.errors.ErrorSet;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;

fn freeCharClassCallback(alloc: std.mem.Allocator, ptr: ?*syntax.CharClass) void {
    const cls = ptr orelse return;

    alloc.free(cls.ranges);
    alloc.free(cls.chars);
}

fn flagSwitch(node: *syntax.Node, flags: syntax.Flags) ?opcodes.Instruction {
    return switch(node) {
        .Literal => opcodes.InstructionFlagSwitch.get(.{ 
            .on = opcodes.Instruction.RuneIgnoreCase, 
            .off = opcodes.Instruction.Rune 
        }, flags),
        .CharClass => opcodes.InstructionFlagSwitch.get(.{ 
            .on = opcodes.Instruction.CharClassIgnoreCase, 
            .off = opcodes.Instruction.CharClass 
        }, flags),
        .StartAnchor => opcodes.InstructionFlagSwitch.get(.{ 
            .on = opcodes.Instruction.AnchorStartMultiline, 
            .off = opcodes.Instruction.AnchorStart 
        }, flags),
        .EndAnchor => opcodes.InstructionFlagSwitch.get(.{ 
            .on = opcodes.Instruction.AnchorEndMultiline, 
            .off = opcodes.Instruction.AnchorEnd 
        }, flags),
        .AnyChar => opcodes.InstructionFlagSwitch.get(.{ 
            .on = opcodes.Instruction.AnyDotAll, 
            .off = opcodes.Instruction.Any 
        }, flags),
        else => null,
    };
}

pub const CharClassBuffer = T_ManagedArrayList(syntax.CharClass, freeCharClassCallback);

pub const Compiler = struct {
    code_buf: BytecodeBuffer,
    class_buf: CharClassBuffer,
    flags: syntax.Flags,

    pub fn init(alloc: std.mem.Allocator) ErrorSet!Compiler {
        return .{
            .code_buf = try BytecodeBuffer.init(alloc, null),
            .class_buf = try CharClassBuffer.init(alloc, null),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.code_buf.deinit();
        self.class_buf.deinit();
        self.* = undefined;
    }

    pub fn emit(self: *Compiler, opcode: opcodes.Instruction) ErrorSet!usize {
        const pos = self.code_buf.len();
        try self.code_buf.append(@intFromEnum(opcode));
        return pos;
    }

    pub fn emitSave(self: *Compiler, slot: usize) ErrorSet!usize {
        const pos = try self.emit(.Save);
        try opcodes.write(.Save, &self.code_buf, slot);
        return pos;
    }

    pub fn emitJump(self: *Compiler, target: usize) ErrorSet!usize {
        const pos = try self.emit(.Jump);
        try opcodes.write(.Jump, &self.code_buf, target);
        return pos;
    }

    pub fn patchJump(self: *Compiler, jump_idx: usize, target: usize) void {
        opcodes.patch(.Jump, &self.code_buf, jump_idx + 1, target);
    }

    pub fn emitSplit(self: *Compiler, left: usize, right: usize) ErrorSet!usize {
        const pos = try self.emit(.Split);
        try opcodes.write(.Split, &self.code_buf, left);
        try opcodes.write(.Split, &self.code_buf, right);
        return pos;
    }

    pub fn patchSplit(self: *Compiler, split_idx: usize, left: usize, right: usize) void {
        const nbytes = @sizeOf(u32);
        opcodes.patch(.Split, &self.code_buf, split_idx + 1, left);
        opcodes.patch(.Split, &self.code_buf, split_idx + 1 + nbytes, right);
    }
};

