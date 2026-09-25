const std = @import("std");
const types = @import("types");
const states = @import("../states.zig");
const syntax = @import("../syntax.zig");
const opcodes = @import("./opcodes.zig");
const operands = @import("./operands.zig");
pub const Instruction = @import("./instruction.zig");
const ErrorSet = types.errors.ErrorSet;
const CompileBuffers = states.CompileBuffers;
const ByteBuffer = states.ByteBuffer;

pub const readOpcode = opcodes.readOpcode;
pub const readOperand = operands.readOperand;
pub fn readFlags(prog: []const u8, pc: *usize) ErrorSet!syntax.Flags {
    if (pc.* >= prog.len) return ErrorSet.OutOfRange;

    const bitmask = prog[pc.*];
    pc.* += 1;

    return syntax.Flags.fromIntBitmask(bitmask);
}

pub const OpCode = opcodes.OpCode;
pub const operandsInfo = operands.operandsInfo;
pub const OperandType = operands.OperandType;

// pub fn decompile(start_byte: ) Instruction {

// }

pub fn emit(ptr: *CompileBuffers, comptime opcode: OpCode, operand: ?OperandType(opcode)) ErrorSet!usize {
    const pos = ptr.prog.len();

    try ptr.prog.append(@intFromEnum(opcode));

    if (opcode.usesFlags()) try ptr.prog.append(ptr.flags.toIntBitmask());

    if (comptime operandsInfo(opcode) != null) {
        const data = operand orelse return ErrorSet.InvalidArgument;

        try operands.writeOperand(opcode, &ptr.prog, data);
    }
    return pos;
}

/// Split requires a separate emit since this instruction takes two operands unlike others with one or none
pub fn emitSplit(ptr: *CompileBuffers, left: usize, right: usize) ErrorSet!usize {
    const pos = ptr.prog.len();

    try ptr.prog.append(@intFromEnum(OpCode.Split));

    try operands.writeOperand(.Split, &ptr.prog, left);
    try operands.writeOperand(.Split, &ptr.prog, right);

    return pos;
}

pub fn patch(ptr: *CompileBuffers, comptime opcode: OpCode, pos: usize, data: OperandType(opcode)) ErrorSet!void {
    const info = operandsInfo(opcode).?;
    var bytes: [@sizeOf(info.T)]u8 = undefined;

    std.mem.writeInt(info.T, &bytes, @intCast(data), .little);

    try ptr.prog.setSlice(pos + operands.offset(opcode), &bytes);
}

pub fn patchSplit(ptr: *CompileBuffers, pos: usize, left: usize, right: usize) ErrorSet!void {
    const info = comptime operandsInfo(.Split).?;
    const size = @sizeOf(info.T);

    try patch(ptr, .Split, pos, left);
    try patch(ptr, .Split, pos + size, right);
}

test "Should emit serialized instruction ordered as [opcode][flags?][operand?]" {
    const allocator = std.testing.allocator;
    const flags: syntax.Flags = .{ .ignore_case = true };

    var state = try CompileBuffers.init(allocator, flags);
    defer state.deinit();

    _ = try emit(&state, .Rune, 'A');

    const prog = state.prog.items();
    var pc: usize = 0;

    try std.testing.expectEqual(OpCode.Rune, try readOpcode(prog, &pc));
    try std.testing.expectEqual(flags.toIntBitmask(), (try readFlags(prog, &pc)).toIntBitmask());
    try std.testing.expectEqual(@as(u21, 'A'), try readOperand(.Rune, prog, &pc));
    try std.testing.expectEqual(prog.len, pc);
}

test "Should replace both reserved branch targets by patchSplit" {
    const allocator = std.testing.allocator;

    var state = try CompileBuffers.init(allocator, .{});
    defer state.deinit();

    const pos = try emitSplit(&state, 0, 0);
    try patchSplit(&state, pos, 12, 34);

    const prog = state.prog.items();
    var pc: usize = 0;

    try std.testing.expectEqual(OpCode.Split, try readOpcode(prog, &pc));
    try std.testing.expectEqual(@as(usize, 12), try readOperand(.Split, prog, &pc));
    try std.testing.expectEqual(@as(usize, 34), try readOperand(.Split, prog, &pc));
}
