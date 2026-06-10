const std = @import("std");
const AST = @import("ast.zig");
const Error = @import("errors.zig").Error;
const Instruction = @import("bytecode.zig").Instruction;

pub const Compiler = @This();

alloc: std.mem.Allocator,
code: std.ArrayList(Instruction),

pub fn init(alloc: std.mem.Allocator) Compiler {
    return .{
        .alloc = alloc,
        .code = .empty,
    };
}

fn emit(self: *Compiler, inst: Instruction) !usize {
    const idx = self.code.items.len;
    try self.code.append(self.alloc, inst);
    return idx;
}

fn patch(self: *Compiler, idx: usize, inst: Instruction) void {
    self.code.items[idx] = inst;
}

fn compileNode(self: *Compiler, node: *const AST.Node) !void {
    switch (node.*) {
        .Literal => |lit| {
            _ = try self.emit(.{ .Rune = lit.value });
        },
        .AnyChar => {
            _ = try self.emit(.Any);
        },
        .StartAnchor => {
            try self.emit(.AssertStart);
        },
        .EndAnchor => {
            try self.emit(.AssertEnd);
        },
        .CharClass => |cls| {
            try self.emit(.{ .Class = cls });
        },
        .Sequence => |seq| {
            for (seq.nodes) |child| {
                try self.compileNode(child);
            }
        },
        .Repeat => |rep| {
            try self.compileRepeat(rep);
        },
        .Alternation => |alt| {
            try self.compileAlternation(alt);
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

fn compileRepeat(self: *Compiler, rep: AST.Repeat) !void {
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try self.emit(undefined);

        const body_start = self.code.items.len;
        try self.compileNode(rep.node);

        _ = try self.emit(.{ .Jump = split_idx });

        const after = self.code.items.len;

        self.patch(split_idx, .{
            .Split = .{
                .first = body_start,
                .second = after,
            },
        });
        return;
    }

    if (rep.min == 1 and rep.max == null) {
        const body_start = self.code.items.len;

        try self.compileNode(rep.node);

        _ = try self.emit(.{
            .Split = .{
                .first = body_start,
                .second = self.code.items.len + 1,
            },
        });
        return;
    }

    if (rep.min == 0 and rep.max.? == 1) {
        const split_idx = try self.emit(undefined);

        const body_start = self.code.items.len;
        try self.compileNode(rep.node);

        const after = self.code.items.len;

        self.patch(split_idx, .{
            .Split = .{
                .first = body_start,
                .second = after,
            },
        });
        return;
    }
    return Error.UnsupportedRepeat;
}

fn compileAlternation(self: *Compiler, alt: AST.Alternation) !void {
    const split_idx = try self.emit(undefined);

    const left_start = self.code.items.len;
    try self.compileNode(alt.left);

    const jump_idx = try self.emit(undefined);

    const right_start = self.code.items.len;
    try self.compileNode(alt.right);

    const after = self.code.items.len;

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

pub fn compile(self: *Compiler, node: *const AST.Node) ![]Instruction {
    try self.emit(.{ .Save = 0 });
    try self.compileNode(node);
    try self.emit(.{ .Save = 1 });
    try self.emit(.Match);

    return try self.code.toOwnedSlice(self.alloc);
}
