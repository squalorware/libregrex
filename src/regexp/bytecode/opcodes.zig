const std = @import("std");
const types = @import("types");
const operand = @import("./operand.zig");
const ErrorSet = types.errors.ErrorSet;
const Operand = operand.Operand;

/// Set of instructions that use modifiers (flags)
const USE_MOD = std.EnumSet(Opcode).init(.{
    .TESTR = true,
    .TESTCL = true,
    .ASTART = true,
    .AEND = true,
    .TEST = true,
});
/// Metadata table mapping opcodes to respective operand sizes and quantity
const OP_TYPES = std.EnumMap(Opcode, Operand).init(.{
    .SAVE = .{ .bits = 16, .count = 1 },
    .FORK = .{ .bits = 32, .count = 2 },
    .GOTO = .{ .bits = 32, .count = 1 },
    .TESTR = .{ .bits = 32, .count = 1 },
    .TESTCL = .{ .bits = 16, .count = 1 },
    .TESTA = .{ .bits = 8, .count = 1 },
});

pub const Opcode = enum(u8) {
    /// Save the current input position into a capture slot.
    ///
    /// Slots are arranged as pairs:
    /// - slot 0 / 1: whole match start/end
    /// - slot 2 / 3: group 1 start/end
    /// - slot 4 / 5: group 2 start/end
    SAVE = 0x00,
    /// Branching instruction. Saves backtracking state at `.raddr`
    ///
    /// Continue evaluation from `.laddr (u32)`; Push `.raddr (u32)` onto the backtracking stack.
    FORK = 0x01,
    /// Unconditional jump to `.addr (u32)`
    GOTO = 0x02,
    /// Match one exact Unicode code point
    TESTR = 0x03,
    /// Match one code point against a character class
    TESTCL = 0x04,
    /// Assert the current input position is the input start
    ASTART = 0x05,
    /// Assert the current input position is the input end
    AEND = 0x06,
    /// Assert word boundaries or global input boundaries
    TESTA = 0x07,
    /// Match any single Unicode code point
    TEST = 0x08,
    /// Terminal instruction;
    RETURN = 0x09,

    /// Get operand metadata for given opcode
    pub fn opInfo(comptime opcode: Opcode) ?Operand {
        return comptime OP_TYPES.get(opcode);
    }

    pub fn id(self: Opcode) []const u8 {
        return std.mem.span(@tagName(self));
    }

    pub fn usesFlags(self: Opcode) bool {
        return USE_MOD.contains(self);
    }

    pub fn hasOperands(self: Opcode) bool {
        return OP_TYPES.contains(self);
    }

    pub fn read(buffer: []const u8, pc: usize) ErrorSet!Opcode {
        if (pc >= buffer.len) return ErrorSet.OutOfRange;

        const data = buffer[pc];

        if (data > @intFromEnum(Opcode.RETURN)) {
            return ErrorSet.InvalidArgument;
        }
        return @enumFromInt(data);
    }

    pub fn offset(self: Opcode) usize {
        return 1 + @intFromBool(self.usesFlags());
    }
};

test "usesFlags identifies flag-sensitive opcodes" {
    try std.testing.expect(Opcode.TESTR.usesFlags());
    try std.testing.expect(Opcode.TESTCL.usesFlags());
    try std.testing.expect(!Opcode.GOTO.usesFlags());
    try std.testing.expect(!Opcode.RETURN.usesFlags());
}

test "readOpcode decodes one byte and advances the program counter" {
    const prog = [_]u8{@intFromEnum(Opcode.TESTR)};
    var pc: usize = 0;

    try std.testing.expectEqual(Opcode.TESTR, try Opcode.read(&prog, &pc));
    try std.testing.expectEqual(@as(usize, 1), pc);
}
