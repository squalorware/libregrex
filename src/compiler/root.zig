const std = @import("std");
const AST = @import("./parser/ast.zig");
const Error = @import("../common/errors.zig").Error;
const Rune = @import("../common/types.zig").Rune;
const Instruction = @import("./icr.zig").Instruction;

pub const Compiler = @This();
const CompilerError = Error || std.mem.Allocator.Error;

alloc: std.mem.Allocator,
bytecode: std.ArrayList(Instruction),

pub fn init(alloc: std.mem.Allocator) Compiler {
    return .{
        .alloc = alloc,
        .bytecode = .empty,
    };
}

fn emit(self: *Compiler, inst: Instruction) !usize {
    const idx = self.bytecode.items.len;
    try self.bytecode.append(self.alloc, inst);
    return idx;
}

fn patch(self: *Compiler, idx: usize, inst: Instruction) void {
    self.bytecode.items[idx] = inst;
}

fn compileNode(self: *Compiler, node: *const AST.Node) CompilerError!void {
    switch (node.*) {
        .Literal => |lit| {
            _ = try self.emit(.{ .Rune = lit.value });
        },
        .AnyChar => {
            _ = try self.emit(.Any);
        },
        .StartAnchor => {
            _ = try self.emit(.AssertStart);
        },
        .EndAnchor => {
            _ =try self.emit(.AssertEnd);
        },
        .CharClass => |cls| {
            const owned = try self.cloneCharClass(cls);
            _ = try self.emit(.{ .Class = owned });
        },
        .Sequence => |seq| {
            for (seq.nodes) |child| {
                try self.compileNode(child);
            }
        },
        .Repeat => |rep| {
            try self.compileRepeat(rep);
        },
        .Branch => |branch| {
            try self.compileBranch(branch);
        },
        .CaptureGroup => |grp| {
            _ = try self.emit(.{ .Save = grp.pos * 2 });
            try self.compileNode(grp.node);
            _ = try self.emit(.{ .Save = grp.pos * 2 + 1 });
        },
        .NonCaptureGroup => |grp| {
            try self.compileNode(grp.node);
        },
    }
}

fn cloneCharClass(self: *Compiler, cls: AST.CharClass) CompilerError!AST.CharClass {
    const ranges = try self.alloc.dupe(AST.CharRange, cls.ranges);
    errdefer self.alloc.free(ranges);

    const chars = try self.alloc.dupe(Rune, cls.chars);
    errdefer self.alloc.free(chars);

    return .{
        .ranges = ranges,
        .chars = chars,
        .negated = cls.negated,
    };
}

fn compileRepeat(self: *Compiler, rep: AST.Repeat) CompilerError!void {
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try self.emit(undefined);

        const body_start = self.bytecode.items.len;
        try self.compileNode(rep.node);

        _ = try self.emit(.{ .Jump = split_idx });

        const after = self.bytecode.items.len;

        self.patch(split_idx, .{
            .Split = .{
                .first = body_start,
                .second = after,
            },
        });
        return;
    }

    if (rep.min == 1 and rep.max == null) {
        const body_start = self.bytecode.items.len;

        try self.compileNode(rep.node);

        _ = try self.emit(.{
            .Split = .{
                .first = body_start,
                .second = self.bytecode.items.len + 1,
            },
        });
        return;
    }

    if (rep.min == 0 and rep.max.? == 1) {
        const split_idx = try self.emit(undefined);

        const body_start = self.bytecode.items.len;
        try self.compileNode(rep.node);

        const after = self.bytecode.items.len;

        self.patch(split_idx, .{
            .Split = .{
                .first = body_start,
                .second = after,
            },
        });
        return;
    }
    return Error.InvalidRepeat;
}

fn compileBranch(self: *Compiler, branch: AST.Branch) CompilerError!void {
    const split_idx = try self.emit(undefined);

    const left_start = self.bytecode.items.len;
    try self.compileNode(branch.left);

    const jump_idx = try self.emit(undefined);

    const right_start = self.bytecode.items.len;
    try self.compileNode(branch.right);

    const after = self.bytecode.items.len;

    self.patch(split_idx, .{
        .Split = .{
            .first = left_start,
            .second = right_start,
        },
    });

    self.patch(jump_idx, .{
        .Jump = after,
    });
}

pub fn compile(self: *Compiler, node: *const AST.Node) CompilerError![]Instruction {
    _ = try self.emit(.{ .Save = 0 });
    _ = try self.compileNode(node);
    _ = try self.emit(.{ .Save = 1 });
    _ = try self.emit(.Match);

    return try self.bytecode.toOwnedSlice(self.alloc);
}

const testing = std.testing;

test "Should compile a sequence of literals" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    const tree = try ast_alloc.alloc(*AST.Node, 3);
    const chars = [_]Rune {'a', 'b', 'c'};
    for (chars, 0..) |ch, i| {
        const node = try ast_alloc.create(AST.Node);
        node.* = .{ .Literal = .{ .value = ch } };
        tree[i] = node;
    }

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    var compiler = Compiler.init(allocator);
    const opcodes = try compiler.compile(root);
    defer allocator.free(opcodes);

    try testing.expectEqual(@as(usize, 6), opcodes.len);

    try testing.expect(opcodes[0] == Instruction.Save);
    try testing.expectEqual(@as(usize, 0), opcodes[0].Save);

    for (chars, 0..) |ch, i| {
        const pos = i + 1;
        try testing.expect(opcodes[pos] == Instruction.Rune);
        try testing.expectEqual(@as(Rune, ch), opcodes[pos].Rune);
    }

    try testing.expect(opcodes[4] == Instruction.Save);
    try testing.expectEqual(@as(usize, 1), opcodes[4].Save);

    try testing.expect(opcodes[5] == Instruction.Match);
}
