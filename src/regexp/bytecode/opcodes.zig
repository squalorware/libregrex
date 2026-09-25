const std = @import("std");
const types = @import("types");
const ByteBuffer = @import("../states.zig").ByteBuffer;
const ErrorSet = types.errors.ErrorSet;

pub const OpCode = enum(u8) {
    /// Save the current input position into a capture slot.
    ///
    /// Slots are arranged as pairs:
    /// - slot 0 / 1: whole match start/end
    /// - slot 2 / 3: group 1 start/end
    /// - slot 4 / 5: group 2 start/end
    Save = 0x00,
    /// Branching instruction
    ///
    /// Execution proceeds with `.left` while `.right` is pushed onto the backtracking stack.
    Split = 0x01,
    /// An unconditional jump to another bytecode offset
    Jump = 0x02,
    /// Match one exact Unicode code point
    Rune = 0x03,
    /// Match one code point against a character class
    CharClass = 0x04,
    /// Assert the current input position is the input start
    AnchorStart = 0x05,
    /// Assert the current input position is an input end
    AnchorEnd = 0x06,
    /// Assert word boundaries or global input boundaries
    Assert = 0x07,
    /// Match any single Unicode code point
    Any = 0x08,
    /// Terminal instruction; matching was successful
    Match = 0x09,

    pub fn usesFlags(self: OpCode) bool {
        return switch (self) {
            .Rune,
            .CharClass,
            .AnchorStart,
            .AnchorEnd,
            .Any,
            => true,

            else => false,
        };
    }
};

pub fn readOpcode(prog: []const u8, pc: *usize) ErrorSet!OpCode {
    if (pc.* >= prog.len) return ErrorSet.OutOfRange;

    const raw = prog[pc.*];
    pc.* += 1;

    if (raw > @intFromEnum(OpCode.Match)) {
        return ErrorSet.InvalidArgument;
    }

    return @enumFromInt(raw);
}

test "usesFlags identifies flag-sensitive opcodes" {
    try std.testing.expect(OpCode.Rune.usesFlags());
    try std.testing.expect(OpCode.CharClass.usesFlags());
    try std.testing.expect(!OpCode.Jump.usesFlags());
    try std.testing.expect(!OpCode.Match.usesFlags());
}

test "readOpcode decodes one byte and advances the program counter" {
    const prog = [_]u8{@intFromEnum(OpCode.Rune)};
    var pc: usize = 0;

    try std.testing.expectEqual(OpCode.Rune, try readOpcode(&prog, &pc));
    try std.testing.expectEqual(@as(usize, 1), pc);
}
