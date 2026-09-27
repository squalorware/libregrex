const std = @import("std");
const types = @import("types");
const formatStr = types.formatStr;
const ErrorSet = types.errors.ErrorSet;
const Opcode = @import("./opcodes.zig").Opcode;
// const operands = @import("./operands.zig");
const Flags = @import("../syntax.zig").Flags;

pub fn FieldView(comptime T: type) type {
    return struct {
        data: T,
        ip: usize = 0,
    };
}

pub fn InstructionView(comptime T: type, op: FieldView(Opcode), mode: ?FieldView(Flags), data: ?FieldView(T)) type {
    return struct {
        const Self = @This();
        opcode: FieldView(Opcode) = op,
        flags: ?FieldView(Flags) = mode,
        operands: ?FieldView(T) = data,

        pub fn name(self: Self) []const u8 {
            return std.mem.span(@tagName(self.opcode.data));
        }

        // pub fn repr(self: Self, alloc: std.mem.Allocator) ErrorSet![]u8 {

        // }
    };
}
// pub fn Instruction(comptime T: type, comptime op: OpCode, flags: ?syntax.Flags, data: ?T) type {
//     return struct {
//         opcode: OpCode = op,
//         opmode: ?syntax.Flags = flags,
//         opvals: ?T = data,
//     };
// }
