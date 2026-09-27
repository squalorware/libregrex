const std = @import("std");
const types = @import("types");
const ErrorSet = types.errors.ErrorSet;
const Opcode = @import("./opcodes.zig").Opcode;
const ByteBuffer = @import("../states.zig").ByteBuffer;

pub fn T_Operand(comptime opcode: Opcode) type {
    comptime {
        const meta = opcode.opInfo() orelse
            compErr("Opcode {X:0>2} {s} assumes no operands", .{ opcode, opcode.id() });

        return @Int(.unsigned, meta.bits);
    }
}

pub const Operand = struct {
    bits: u16,
    count: usize,

    pub fn size(self: Operand) usize {
        return self.bits / 8;
    }
};

pub fn writeOperand(comptime opcode: Opcode, buffer: *ByteBuffer, data: anytype) ErrorSet!void {
    const info = opcode.opInfo().?;
    comptime var bytes: [info.size()]u8 = undefined;

    std.mem.writeInt(T_Operand(opcode), &bytes, @intCast(data), .little);

    try buffer.appendSlice(&bytes);
}

pub fn readOperand(comptime opcode: Opcode, prog: []const u8, pc: *usize) ErrorSet!u32 {
    const info = opcode.opInfo().?;
    const nbytes = info.size();

    if (pc.* + nbytes > prog.len) return ErrorSet.OutOfRange;

    const value = std.mem.readInt(T_Operand(opcode), prog[pc.*..][0..nbytes], .little);

    pc.* += nbytes;
    return @intCast(value);
}

fn compErr(comptime fmt: []const u8, args: anytype) noreturn {
    const alloc = std.heap.page_allocator;
    const msg: []const u8 = try types.formatStr(alloc, fmt, args);
    @compileError(msg);
}

test "Should encode .SAVE operand as a two-byte integer" {
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
