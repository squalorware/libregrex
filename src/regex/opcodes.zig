const std = @import("std");
const types = @import("types");
const syntax = @import("./syntax.zig");
const ErrorSet = types.errors.ErrorSet;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;

pub const BytecodeBuffer = T_ManagedArrayList(u8, null);

pub const Instruction = enum(u8) {
    /// Save the current input position into a capture slot.
    ///
    /// Slots are arranged as pairs:
    /// - slot 0 / 1: whole match start/end
    /// - slot 2 / 3: group 1 start/end
    /// - slot 4 / 5: group 2 start/end
    Save                 = 0x00,
    /// Branching instruction
    ///
    /// Execution proceeds with `.left` while `.right` is pushed onto the backtracking stack.
    Split                = 0x01,
    /// An unconditional jump to another bytecode offset
    Jump                 = 0x02,
    /// Match one exact Unicode code point
    Rune                 = 0x03,
    /// Match one exact Unicode code point ignoring character case
    RuneIgnoreCase       = 0x04,
    /// Match one code point against a character class
    CharClass            = 0x05,
    /// Match one code point against a character class ignoring character case
    CharClassIgnoreCase  = 0x06,
    /// Assert the current input position is the input start
    AnchorStart          = 0x07,
    /// Assert the current input position is an input start or new line start
    AnchorStartMultiline = 0x08,
    /// Assert the current input position is an input end
    AnchorEnd            = 0x09,
    /// Assert the current input position is an input end or new line end
    AnchorEndMultiline   = 0x0A,
    /// Assert word boundaries or global input boundaries
    Assert               = 0x0B,
    /// Match any single Unicode code point
    Any                  = 0x0C,
    /// Match any single Unicode code point including new line characters
    AnyDotAll            = 0x0D,
    /// Terminal instruction; matching was successful
    Match                = 0x0E,

    pub fn opInfo(comptime self: Instruction) ?OperandInfo {
        return switch(self) {
            .Save                => .{ .S = usize, .T = u16, },
            .Split               => .{ .S = usize, .T = u32, },
            .Jump                => .{ .S = usize, .T = u32, },
            .Rune                => .{ .S = u21, .T = u32, },
            .RuneIgnoreCase      => .{ .S = u21, .T = u32, },
            .CharClass           => .{ .S = usize, .T = u16, },
            .CharClassIgnoreCase => .{ .S = usize, .T = u16, },
            .Assert              => .{ .S = u8, .T = u8, },
            else => null,
        };
    }
};

const SwitchOptions = struct {
    on: Instruction,
    off: Instruction,
};

pub const InstructionFlagSwitch = union(enum) {
    Rune: SwitchOptions,
    CharClass: SwitchOptions,
    AnchorStart: SwitchOptions,
    AnchorEnd: SwitchOptions,
    Any: SwitchOptions,

    pub fn get(pair: InstructionFlagSwitch, flags: syntax.Flags) Instruction {
        return switch(pair) {
            .Rune, .CharClass => if (flags.ignore_case) pair.on else pair.off,
            .AnchorStart, .AnchorEnd => if (flags.multiline) pair.on else pair.off,
            .Any =>  if (flags.dot_all) pair.on else pair.off,
        };
    }
};

const OperandInfo = struct {
    /// Source type
    S: type,
    /// Target type
    T: type,
};

pub fn T_SourceInt(comptime opcode: Instruction) type {
    const info = opcode.opInfo() orelse @compileError("Instruction has no operand");

    return info.S;
}

pub fn write(comptime opcode: Instruction, buffer: *BytecodeBuffer, data: T_SourceInt(opcode)) !void {
    const info = opcode.opInfo().?;
    var bytes: [@sizeOf(info.T)]u8 = undefined;

    std.mem.writeInt(
        info.T,
        &bytes,
        @intCast(data),
        .little,
    );

    try buffer.appendSlice(&bytes);
}

pub fn read(comptime opcode: Instruction, buffer: *BytecodeBuffer, pc: *usize) T_SourceInt(opcode) {
    const info = opcode.opInfo().?;
    const nbytes = @sizeOf(info.T);

    const code = buffer.items();
    const value = std.mem.readInt(
        info.T,
        code[pc.*..][0..nbytes],
        .little,
    );

    pc.* += nbytes;

    return @intCast(value);
}

pub fn patch(comptime opcode: Instruction, buffer: *BytecodeBuffer, pos: usize, data: T_SourceInt(opcode)) void {
    const info = opcode.opInfo().?;
    const nbytes = @sizeOf(info.T);

    var bytes: [nbytes]u8 = undefined;
    std.mem.writeInt(info.T, &bytes, @intCast(data), .little);

    try buffer.patch(pos, &bytes);
}
