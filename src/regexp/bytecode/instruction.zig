const opcodes = @import("./opcodes.zig");
const syntax = @import("../syntax.zig");

/// Occupies 1 byte (opcode), has no flags or operands
const NoOperand = packed struct(u8) {
    opcode: opcodes.OpCode,
};
/// Occupies 2 bytes (1 byte opcode + 1 byte flags)
const NoOperandFlagged = packed struct(u16) {
    opcode: opcodes.OpCode,
    mode: syntax.Flags,
};
/// Occupies 2 bytes (1 byte opcode + 1 byte operand)
const UInt8Operand = packed struct(u16) {
    opcode: opcodes.OpCode,
    data: u8,
};
/// Occupies 3 bytes (1 byte opcode + 1 byte flags + 1 byte operand)
const UInt8OperandFlagged = packed struct(u24) {
    opcode: opcodes.OpCode,
    mode: syntax.Flags,
    data: u8,
};
/// Occupies 3 bytes (1 byte opcode + 2 byte operand)
const UInt16Operand = packed struct(u24) {
    opcode: opcodes.OpCode,
    data: u16,
};
/// Occupies 4 bytes (1 byte opcode + 1 byte flag + 2 bytes operand)
const UInt16OperandFlagged = packed struct(u32) {
    opcode: opcodes.OpCode,
    mode: syntax.Flags,
    data: u16,
};
/// Occupies 5 bytes (1 byte opcode + 4 bytes operand)
const UInt32Operand = packed struct(u40) {
    opcode: opcodes.OpCode,
    data: u32,
};
/// Occupies 6 bytes (1 byte opcode + 1 byte flag + 4 bytes operand)
const UInt32OperandFlagged = packed struct(u48) {
    opcode: opcodes.OpCode,
    mode: syntax.Flags,
    data: u32,
};
/// Occupies 10 bytes (1 byte opcode + 1 byte flag + 4 bytes operand + 4 bytes operand)
const DualUInt32OperandFlagged = packed struct(u80) { opcode: opcodes.OpCode, mode: syntax.Flags, ldata: u32, rdata: u32 };

pub const Instruction = union(enum) {
    NoOperand: NoOperand,
    NoOperandFlagged: NoOperandFlagged,
    UInt8Operand: UInt8Operand,
    UInt8OperandFlagged: UInt8OperandFlagged,
    UInt16Operand: UInt16Operand,
    UInt16OperandFlagged: UInt16OperandFlagged,
    UInt32OperandFlagged: UInt32OperandFlagged,
    DualUInt32OperandFlagged: DualUInt32OperandFlagged,
};
