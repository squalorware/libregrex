const std = @import("std");
const types = @import("types");
const bytecode = @import("./bytecode/root.zig");
const states = @import("./states.zig");
const syntax = @import("./syntax.zig");
const ErrorSet = types.errors.ErrorSet;
const CompileBuffers = states.CompileBuffers;

pub fn compileNode(ptr: *CompileBuffers, node: *syntax.Node) ErrorSet!void {
    switch (node.*) {
        .Literal => |literal| {
            _ = try bytecode.emit(ptr, .Rune, literal.value);
        },
        .AnyChar => {
            _ = try bytecode.emit(ptr, .Any, null);
        },
        .StartAnchor => {
            _ = try bytecode.emit(ptr, .AnchorStart, null);
        },
        .EndAnchor => {
            _ = try bytecode.emit(ptr, .AnchorEnd, null);
        },
        .Assertion => |assertion| {
            _ = try bytecode.emit(ptr, .Assert, @intFromEnum(assertion.typ));
        },
        .CharClass => |cls| {
            const index = try ptr.cloneCharClass(cls);

            _ = try bytecode.emit(ptr, .CharClass, index);
        },
        .Sequence => |seq| {
            // const owned = try ptr.cloneSequence(seq);

            // defer ptr.alloc.free(owned.nodes);

            for (seq.nodes) |child| {
                try compileNode(ptr, child);
            }
        },
        .Branch => |branch| {
            try compileBranch(ptr, branch);
        },
        .Repeat => |rep| {
            try compileRepeat(ptr, rep);
        },
        .CaptureGroup => |grp| {
            try compileCaptureGroup(ptr, grp);
        },
        .NonCaptureGroup => |grp| {
            try compileNode(ptr, grp.node);
        },
    }
}

/// Emits bytecode for alternation operator (`|` PIPE)
fn compileBranch(ptr: *CompileBuffers, branch: syntax.Branch) ErrorSet!void {
    const split = try bytecode.emitSplit(ptr, 0, 0);

    const left = ptr.prog.len();
    try compileNode(branch.left);

    const jmp = try bytecode.emit(ptr, .Jump, 0);

    const right = ptr.prog.len();
    try compileNode(branch.right);

    const after = ptr.prog.len();
    try bytecode.patchSplit(ptr, split, left, right);
    try bytecode.patch(ptr, .Jump, jmp, after);
}

/// Emits bytecode for supported postfix quantifiers
fn compileRepeat(ptr: *CompileBuffers, rep: syntax.Repeat) ErrorSet!void {
    // '*' STAR (zero or more)
    if (rep.min == 0 and rep.max == null) {
        const split = try bytecode.emitSplit(ptr, 0, 0);

        const body = ptr.prog.len();
        try compileNode(ptr, rep.node);

        _ = try bytecode.emit(ptr, .Jump, split);
        const after = ptr.prog.len();

        try bytecode.patchSplit(ptr, split, body, after);
        return;
    }
    // '+' PLUS (one or more)
    if (rep.min == 1 and rep.max == null) {
        const body = ptr.prog.len();
        try compileNode(ptr, rep.node);

        const split = try bytecode.emitSplit(ptr, body, 0);
        const after = ptr.prog.len();

        try bytecode.patchSplit(ptr, split, body, after);
        return;
    }
    // '?' QUESTION (zero or one)
    if (rep.min == 0 and rep.max != null and rep.max.? == 1) {
        const split = try bytecode.emitSplit(ptr, 0, 0);

        const body = ptr.prog.len();
        try compileNode(ptr, rep.node);

        const after = ptr.prog.len();
        try bytecode.patchSplit(ptr, split, body, after);

        return;
    }
    return ErrorSet.InvalidRepeat;
}

fn compileCaptureGroup(ptr: *CompileBuffers, grp: syntax.CaptureGroup) ErrorSet!void {
    const start_slot = grp.pos * 2;
    const end_slot = start_slot + 1;

    _ = try bytecode.emit(ptr, .Save, start_slot);
    try compileNode(ptr, grp.node);
    _ = try bytecode.emit(ptr, .Save, end_slot);
}

test "compileNode lowers alternation to Split and Jump" {
    const allocator = std.testing.allocator;

    var state = try CompileBuffers.init(allocator, .{});
    defer state.deinit();

    var left: syntax.Node = .{ .Literal = .{ .value = 'a' } };
    var right: syntax.Node = .{ .Literal = .{ .value = 'b' } };
    var root: syntax.Node = .{
        .Branch = .{
            .left = &left,
            .right = &right,
        },
    };

    try compileNode(&state, &root);

    const prog = state.prog.items();
    var pc: usize = 0;

    try std.testing.expectEqual(bytecode.OpCode.Split, try bytecode.readOpcode(prog, &pc));
    const left_target = try bytecode.readOperand(.Split, prog, &pc);
    const right_target = try bytecode.readOperand(.Split, prog, &pc);
    try std.testing.expectEqual(pc, left_target);

    try std.testing.expectEqual(bytecode.OpCode.Rune, try bytecode.readOpcode(prog, &pc));
    _ = try bytecode.readFlags(prog, &pc);
    try std.testing.expectEqual(@as(u21, 'a'), try bytecode.readOperand(.Rune, prog, &pc));

    try std.testing.expectEqual(bytecode.OpCode.Jump, try bytecode.readOpcode(prog, &pc));
    const after = try bytecode.readOperand(.Jump, prog, &pc);
    try std.testing.expectEqual(pc, right_target);

    try std.testing.expectEqual(bytecode.OpCode.Rune, try bytecode.readOpcode(prog, &pc));
    _ = try bytecode.readFlags(prog, &pc);
    try std.testing.expectEqual(@as(u21, 'b'), try bytecode.readOperand(.Rune, prog, &pc));
    try std.testing.expectEqual(pc, after);
}

test "compileNode lowers optional repeat to a skippable branch" {
    const allocator = std.testing.allocator;

    var state = try CompileBuffers.init(allocator, .{});
    defer state.deinit();

    var literal: syntax.Node = .{ .Literal = .{ .value = 'a' } };
    var root: syntax.Node = .{
        .Repeat = .{
            .node = &literal,
            .min = 0,
            .max = 1,
        },
    };

    try compileNode(&state, &root);

    const prog = state.prog.items();
    var pc: usize = 0;

    try std.testing.expectEqual(bytecode.OpCode.Split, try bytecode.readOpcode(prog, &pc));
    const body = try bytecode.readOperand(.Split, prog, &pc);
    const after = try bytecode.readOperand(.Split, prog, &pc);
    try std.testing.expectEqual(pc, body);

    try std.testing.expectEqual(bytecode.OpCode.Rune, try bytecode.readOpcode(prog, &pc));
    _ = try bytecode.readFlags(prog, &pc);
    try std.testing.expectEqual(@as(u21, 'a'), try bytecode.readOperand(.Rune, prog, &pc));
    try std.testing.expectEqual(pc, after);
}
