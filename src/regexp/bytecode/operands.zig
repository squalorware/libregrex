const std = @import("std");
const types = @import("types");
const ErrorSet = types.errors.ErrorSet;
const OpCode = @import("./opcodes.zig").OpCode;
const ByteBuffer = @import("../states.zig").ByteBuffer;

pub const OperandInfo = struct {
    S: type,
    T: type,
};

pub fn operandsInfo(comptime opcode: OpCode) ?OperandInfo {
    return switch (opcode) {
        .Save => .{ .S = usize, .T = u16 },
        .Split, // Don't forget .Split receives two u32 operands
        .Jump,
        => .{ .S = usize, .T = u32 },
        .Rune => .{ .S = u21, .T = u32 },
        .CharClass => .{ .S = usize, .T = u16 },
        .Assert => .{ .S = u8, .T = u8 },
        else => null,
    };
}

pub fn OperandType(comptime opcode: OpCode) type {
    if (operandsInfo(opcode)) |info| {
        return info.S;
    }
    return void;
}

pub fn offset(comptime opcode: OpCode) usize {
    return 1 + @intFromBool(opcode.usesFlags());
}

pub fn writeOperand(comptime opcode: OpCode, buffer: *ByteBuffer, data: OperandType(opcode)) ErrorSet!void {
    const info = operandsInfo(opcode).?;
    var bytes: [@sizeOf(info.T)]u8 = undefined;

    std.mem.writeInt(info.T, &bytes, @intCast(data), .little);

    try buffer.appendSlice(&bytes);
}

pub fn readOperand(comptime opcode: OpCode, prog: []const u8, pc: *usize) ErrorSet!OperandType(opcode) {
    const info = operandsInfo(opcode).?;
    const nbytes = @sizeOf(info.T);

    if (pc.* + nbytes > prog.len) return ErrorSet.OutOfRange;

    const value = std.mem.readInt(info.T, prog[pc.*..][0..nbytes], .little);

    pc.* += nbytes;
    return @intCast(value);
}

test "Should encode .Save operand as a two-byte integer" {
    const allocator = std.testing.allocator;

    var buffer = try ByteBuffer.init(allocator, null);
    defer buffer.deinit();

    try writeOperand(.Save, &buffer, 0x1234);

    try std.testing.expectEqual(@as(usize, 2), buffer.len());
    try std.testing.expectEqual(@as(u8, 0x34), buffer.items()[0]);
    try std.testing.expectEqual(@as(u8, 0x12), buffer.items()[1]);

    var pc: usize = 0;
    try std.testing.expectEqual(@as(usize, 0x1234), try readOperand(.Save, buffer.items(), &pc));
}

test "Should preserve a non-ASCII u21 value through u32 encoding" {
    const allocator = std.testing.allocator;

    var buffer = try ByteBuffer.init(allocator, null);
    defer buffer.deinit();

    try writeOperand(.Rune, &buffer, 'Ж');

    try std.testing.expectEqual(@as(usize, 4), buffer.len());

    var pc: usize = 0;
    try std.testing.expectEqual(@as(u21, 'Ж'), try readOperand(.Rune, buffer.items(), &pc));
}
