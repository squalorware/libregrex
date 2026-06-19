//! AST-to-bytecode compiler.
//! 
//! Consumes the AST produced by parser and emits 
//! a bytecode `Instruction` stream for the backtracking VM.
const std = @import("std");
const AST = @import("./ast.zig");
const RegrexError = @import("../common/errors.zig").RegrexError;
const Rune = @import("../common/types.zig").Rune;
const Instruction = @import("./icr.zig").Instruction;

pub const Self = @This();

alloc: std.mem.Allocator,
bytecode: std.ArrayList(Instruction),

/// Initializes a compiler state and 
/// allocates bytecode dynamic buffer
pub fn init(alloc: std.mem.Allocator) Self {
    return .{
        .alloc = alloc,
        .bytecode = .empty,
    };
}

/// Appends an `Instruction` and returns its bytecode index 
fn emit(self: *Self, inst: Instruction) RegrexError!usize {
    const idx = self.bytecode.items.len;
    self.bytecode.append(self.alloc, inst) catch {
        return RegrexError.MemoryError;
    };
    return idx;
}

/// Replaces a previously emitted placeholder `Instruction`.
/// 
/// Used for forward jumps where the target address is unknown
/// until after compiling a branch or repeating body
fn patch(self: *Self, idx: usize, inst: Instruction) void {
    self.bytecode.items[idx] = inst;
}

/// Emit bytecode for an AST Node
fn compileNode(self: *Self, node: *const AST.Node) RegrexError!void {
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

/// Deep-copies a character class into bytecode memory.
/// 
/// Prevents bytecode from pointing into the temporary `Parser` AST arena
fn cloneCharClass(self: *Self, cls: AST.CharClass) RegrexError!AST.CharClass {
    const ranges = self.alloc.dupe(AST.CharRange, cls.ranges) catch {
        return RegrexError.MemoryError;
    };
    errdefer self.alloc.free(ranges);

    const chars = self.alloc.dupe(Rune, cls.chars) catch {
        return RegrexError.MemoryError;
    };
    errdefer self.alloc.free(chars);

    return .{
        .ranges = ranges,
        .chars = chars,
        .negated = cls.negated,
    };
}

/// Emits bytecode for supported postfix quantifiers.
/// 
/// The supported forms are:
/// - `*` (zero or more)
/// - `+` (one to more)
/// - `?` (zero to one)
/// 
/// Returns `Error.InvalidRepeat` for unsupported repeat patterns.
fn compileRepeat(self: *Self, rep: AST.Repeat) RegrexError!void {
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
    return RegrexError.InvalidRepeat;
}

/// Emits bytecode for branching (alternation).
/// 
/// The produced control flow is:
/// - `Split(left, right)`
/// - left branch
/// - `Jump(after)`
/// - right branch
fn compileBranch(self: *Self, branch: AST.Branch) RegrexError!void {
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

/// Top-level callable. Compiles the AST into an owned bytecode slice.
/// 
/// The compiler wraps the whole pattern in capture slot 0/1 for the full match, 
/// then emits `Match` as a terminal instruction.
/// 
/// The caller owns the returned slice and must free it. 
/// If bytecode contains `Class` instructions, their internal slices 
/// must be freed by the owner as well.  
pub fn compile(self: *Self, node: *const AST.Node) RegrexError![]Instruction {
    _ = try self.emit(.{ .Save = 0 });
    _ = try self.compileNode(node);
    _ = try self.emit(.{ .Save = 1 });
    _ = try self.emit(.Match);

    const bc = self.bytecode.toOwnedSlice(self.alloc) catch {
        return RegrexError.MemoryError;
    };
    return bc;
}

const testing = std.testing;

test "Should compile a sequence of literals `abc`" {
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

    var compiler = Self.init(allocator);
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

test "Should compile an anchored lowercase character class repeat `^[a-z]*$`" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    const start = try ast_alloc.create(AST.Node);
    start.* = .{ .StartAnchor = .{} };

    const ranges = try ast_alloc.alloc(AST.CharRange, 1);
    ranges[0] = .{
        .start = 'a',
        .end = 'z',
    };

    const chars = try ast_alloc.alloc(Rune, 0);
    const class_node = try ast_alloc.create(AST.Node);
    class_node.* = .{
        .CharClass = .{
            .ranges = ranges,
            .chars = chars,
            .negated = false,
        },
    };

    const repeat = try ast_alloc.create(AST.Node);
    repeat.* = .{
        .Repeat = .{
            .node = class_node,
            .min = 0,
            .max = null,
        }
    };

    const end = try ast_alloc.create(AST.Node);
    end.* = .{ .EndAnchor = .{} };

    const tree = try ast_alloc.alloc(*AST.Node, 3);
    tree[0] = start;
    tree[1] = repeat;
    tree[2] = end;

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    var compiler = Self.init(allocator);
    const bytecode = try compiler.compile(root);
    defer {
        for (bytecode) |inst| {
            switch(inst) {
                .Class => |cls| {
                    allocator.free(cls.ranges);
                    allocator.free(cls.chars);
                },
                else => {},
            }
        }
        allocator.free(bytecode);
    }

    try testing.expectEqual(@as(usize, 8), bytecode.len);

    try testing.expect(bytecode[0] == .Save);
    try testing.expectEqual(@as(usize, 0), bytecode[0].Save);

    try testing.expect(bytecode[1] == .AssertStart);

    try testing.expect(bytecode[2] == .Split);
    try testing.expectEqual(@as(usize, 3), bytecode[2].Split.first);
    try testing.expectEqual(@as(usize, 5), bytecode[2].Split.second);

    try testing.expect(bytecode[3] == .Class);
    try testing.expectEqual(false, bytecode[3].Class.negated);
    try testing.expectEqual(@as(usize, 1), bytecode[3].Class.ranges.len);
    try testing.expectEqual(@as(Rune, 'a'), bytecode[3].Class.ranges[0].start);
    try testing.expectEqual(@as(Rune, 'z'), bytecode[3].Class.ranges[0].end);

    try testing.expect(bytecode[4] == .Jump);
    try testing.expectEqual(@as(usize, 2), bytecode[4].Jump);

    try testing.expect(bytecode[5] == .AssertEnd);

    try testing.expect(bytecode[6] == .Save);
    try testing.expectEqual(@as(usize, 1), bytecode[6].Save);

    try testing.expect(bytecode[7] == .Match);
}

test "Should compile branching `a|b`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    const left = try ast_alloc.create(AST.Node);
    left.* = .{ .Literal = .{ .value = 'a' } };
    const right = try ast_alloc.create(AST.Node);
    right.* = .{ .Literal = .{ .value = 'b' } };

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .Branch = .{
            .left = left,
            .right = right,
        },
    };

    var compiler = Self.init(allocator);
    const bytecode = try compiler.compile(root);
    defer allocator.free(bytecode);

    try testing.expectEqual(@as(usize, 7), bytecode.len);
    try testing.expect(bytecode[0] == .Save);
    try testing.expectEqual(@as(usize, 0), bytecode[0].Save);

    try testing.expect(bytecode[1] == .Split);
    try testing.expectEqual(@as(usize, 2), bytecode[1].Split.first);
    try testing.expectEqual(@as(usize, 4), bytecode[1].Split.second);

    try testing.expect(bytecode[2] == .Rune);
    try testing.expectEqual(@as(Rune, 'a'), bytecode[2].Rune);

    try testing.expect(bytecode[3] == .Jump);
    try testing.expectEqual(@as(usize, 5), bytecode[3].Jump);

    try testing.expect(bytecode[4] == .Rune);
    try testing.expectEqual(@as(Rune, 'b'), bytecode[4].Rune);

    try testing.expect(bytecode[5] == .Save);
    try testing.expectEqual(@as(usize, 1), bytecode[5].Save);

    try testing.expect(bytecode[6] == .Match);
}

test "Should compile a capture group `(a)`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    const lit = try ast_alloc.create(AST.Node);
    lit.* = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .CaptureGroup = .{
            .pos = 1,
            .node = lit,
        },
    };

    var compiler = Self.init(allocator);
    const bytecode = try compiler.compile(root);
    defer allocator.free(bytecode);

    try testing.expectEqual(@as(usize, 6), bytecode.len);

    try testing.expect(bytecode[0] == .Save);
    try testing.expectEqual(@as(usize, 0), bytecode[0].Save);

    try testing.expect(bytecode[1] == .Save);
    try testing.expectEqual(@as(usize, 2), bytecode[1].Save);

    try testing.expect(bytecode[2] == .Rune);
    try testing.expectEqual(@as(Rune, 'a'), bytecode[2].Rune);

    try testing.expect(bytecode[3] == .Save);
    try testing.expectEqual(@as(usize, 3), bytecode[3].Save);

    try testing.expect(bytecode[4] == .Save);
    try testing.expectEqual(@as(usize, 1), bytecode[4].Save);

    try testing.expect(bytecode[5] == .Match);
}

test "Should compile an optional repeat `a?`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    const lit = try ast_alloc.create(AST.Node);
    lit.* = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .Repeat = .{
            .node = lit,
            .min = 0,
            .max = 1,
        },
    };

    var compiler = Self.init(allocator);
    const bytecode = try compiler.compile(root);
    defer allocator.free(bytecode);

    try testing.expectEqual(@as(usize, 5), bytecode.len);

    try testing.expect(bytecode[0] == .Save);
    try testing.expectEqual(@as(usize, 0), bytecode[0].Save);

    try testing.expect(bytecode[1] == .Split);
    try testing.expectEqual(@as(usize, 2), bytecode[1].Split.first);
    try testing.expectEqual(@as(usize, 3), bytecode[1].Split.second);

    try testing.expect(bytecode[2] == .Rune);
    try testing.expectEqual(@as(Rune, 'a'), bytecode[2].Rune);

    try testing.expect(bytecode[3] == .Save);
    try testing.expectEqual(@as(usize, 1), bytecode[3].Save);

    try testing.expect(bytecode[4] == .Match);
}
