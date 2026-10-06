const std = @import("std");
const types = @import("types");
const states = @import("../states.zig");
const syntax = @import("../syntax.zig");
const opcodes = @import("./opcodes.zig");
const op_mod = @import("./operand.zig");
const view = @import("./view.zig");
const ErrorSet = types.errors.ErrorSet;
const CompileStateBuffer = states.CompileStateBuffer;

pub const InstructionView = view.InstructionView;
pub const Opcode = opcodes.Opcode;
pub const Operand = op_mod.Operand;
pub const T_Operand = op_mod.T_Operand;
pub const readOperand = op_mod.readOperand;

pub fn readFlags(prog: []const u8, pc: usize) ErrorSet!syntax.Flags {
    const bitmask = prog[pc];

    return syntax.Flags.fromIntBitmask(bitmask);
}

pub fn emit(ptr: *CompileStateBuffer, comptime opcode: Opcode, data: anytype) ErrorSet!usize {
    const pos = ptr.len();

    try ptr.append(@intFromEnum(opcode));

    if (opcode.usesFlags()) try ptr.prog.append(ptr.flags.toIntBitmask());

    try op_mod.writeOperand(opcode, &ptr.prog, data);
    return pos;
}

/// Split requires a separate emit since this instruction takes two operands unlike others with one or none
pub fn emitFork(ptr: *CompileStateBuffer, left: usize, right: usize) ErrorSet!usize {
    const pos = ptr.len();

    try ptr.prog.append(@intFromEnum(Opcode.FORK));

    try op_mod.writeOperand(.FORK, &ptr.prog, left);
    try op_mod.writeOperand(.FORK, &ptr.prog, right);

    return pos;
}

pub fn patch(ptr: *CompileStateBuffer, comptime opcode: Opcode, pos: usize, data: T_Operand(opcode)) ErrorSet!void {
    const operand = opcode.opInfo().?;
    var bytes: [operand.size()]u8 = undefined;

    std.mem.writeInt(T_Operand(opcode), &bytes, @intCast(data), .little);

    try ptr.prog.setSlice(pos + opcode.offset(), &bytes);
}

pub fn patchFork(ptr: *CompileStateBuffer, pos: usize, left: usize, right: usize) ErrorSet!void {
    const operand = comptime Opcode.FORK.opInfo().?;

    try patch(ptr, .FORK, pos, left);
    try patch(ptr, .FORK, pos + operand.size(), right);
}

test "Should emit serialized instruction ordered as [opcode][flags?][operand?]" {
    const gpa = std.testing.allocator;
    const flags: syntax.Flags = .{ .ignore_case = true };

    var state = try CompileStateBuffer.init(gpa, flags);
    defer state.deinit();

    _ = try emit(&state.prog, .TESTR, 'A');

    const prog = state.prog.items();
    var pc: usize = 0;

    const opcode = Opcode.TESTR;
    try std.testing.expectEqual(opcode, try Opcode.read(prog, &pc));
    try std.testing.expectEqual(flags.toIntBitmask(), (try readFlags(prog, &pc)).toIntBitmask());
    try std.testing.expectEqual(@as(u32, 'A'), try readOperand(.TESTR, prog, &pc));
    try std.testing.expectEqual(prog.len, pc);
}

test "Should replace both reserved branch targets by patchFork" {
    const gpa = std.testing.allocator;

    var state = try CompileStateBuffer.init(gpa, null);
    defer state.deinit();

    const pos = try emitFork(&state, 0, 0);
    try patchFork(&state, pos, 12, 34);

    const prog = state.prog.items();
    var pc: usize = 0;

    try std.testing.expectEqual(Opcode.FORK, try Opcode.read(prog, &pc));
    try std.testing.expectEqual(@as(u32, 12), try readOperand(.FORK, prog, &pc));
    try std.testing.expectEqual(@as(u32, 34), try readOperand(.FORK, prog, &pc));
}
