//! Bytecode emitter
//!
//! Recursively consumes the abstract syntax tree produced by parser 
//! and emits corresponding bytecode instructions to the program buffer
const std = @import("std");
const types = @import("types");
const syntax = @import("./parsing/syntax.zig");
const Bytecode = @import("./bytecode.zig");
const testing = std.testing;
const Instruction = Bytecode.Instruction;
const InstructionSet = Bytecode.InstructionSet;
const ErrorSet = types.errors.ErrorSet;

/// Deep-copies a char class into memory owned by compiler to avoid emitted `Instruction` pointing into `Parser` arena 
fn cloneCharClass(alloc: std.mem.Allocator, cls: syntax.CharClass) ErrorSet!syntax.CharClass {
    const ranges = alloc.dupe(syntax.RuneRange, cls.ranges) catch {
        return ErrorSet.MemoryError;
    };
    errdefer alloc.free(ranges);

    const chars = alloc.dupe(u21, cls.chars) catch {
        return ErrorSet.MemoryError;
    };
    errdefer alloc.free(chars);

    return .{
        .ranges = ranges,
        .chars = chars,
        .preset = cls.preset,
        .negated_preset = cls.negated_preset,
        .negated = cls.negated,
    };

}

/// Deep-copies a sequence into memory owned by compiler to avoid emitted `Instruction` pointing into `Parser` arena 
fn cloneSequence(alloc: std.mem.Allocator, seq: syntax.Sequence) ErrorSet!syntax.Sequence {
    const nodes = alloc.dupe(*syntax.Node, seq.nodes) catch {
        return ErrorSet.MemoryError;
    };
    errdefer alloc.free(nodes);

    return .{ .nodes = nodes };
}

pub const Compiler = @This();

buffer: *InstructionSet,
flags: syntax.Flags,

pub fn init(prog: *InstructionSet, flags: syntax.Flags) Compiler {
    return .{ .buffer = prog, .flags = flags };
}

fn emit(self: Compiler, inst: Instruction) ErrorSet!usize {
    const idx = self.buffer.len();
    try self.buffer.append(inst);

    return idx;
}

/// Replaces a previously emitted placeholder `Instruction`.
///
/// Used for forward jumps where the target address is unknown until after compiling a branch or repeating body
fn patch(self: Compiler, idx: usize, inst: Instruction) ErrorSet!void {
    try self.buffer.set(idx, inst);
}

/// Consumes a node, emits a correspondent `Instruction` with modifiers
fn compileNode(self: Compiler, alloc: std.mem.Allocator, node: *const syntax.Node) ErrorSet!void {
    switch (node.*) {
        .Literal => |lit| {
            _ = try self.emit(.{
                .Rune = .{
                    .value = lit.value,
                    .ignore_case = self.flags.ignore_case,
                },
            });
        },
        .AnyChar => {
            _ = try self.emit(.{ .Any = .{
                .dot_all = self.flags.dot_all,
            } });
        },
        .StartAnchor => {
            _ = try self.emit(.{
                .AssertStart = .{
                    .multiline = self.flags.multiline,
                },
            });
        },
        .EndAnchor => {
            _ = try self.emit(.{
                .AssertEnd = .{
                    .multiline = self.flags.multiline,
                },
            });
        },
        .Assertion => |assert| {
            _ = try self.emit(.{
                .Assert = assert.typ,
            });
        },
        .CharClass => |cls| {
            const owned = try cloneCharClass(alloc, cls);

            errdefer {
                alloc.free(owned.ranges);
                alloc.free(owned.chars);
            }

            _ = try self.emit(.{
                .Class = .{
                    .class = owned,
                    .ignore_case = self.flags.ignore_case,
                },
            });
        },
        .Sequence => |seq| {
            const owned = try cloneSequence(alloc, seq);

            defer alloc.free(owned.nodes);

            for (owned.nodes) |child| {
                try self.compileNode(alloc, child);
            }
        },
        .Repeat => |rep| {
            try self.compileRepeat(alloc, rep);
        },
        .Branch => |branch| {
            try self.compileBranch(alloc, branch);
        },
        .CaptureGroup => |grp| {
            _ = try self.emit(.{ .Save = grp.pos * 2 });
            try self.compileNode(alloc, grp.node);
            _ = try self.emit(.{ .Save = grp.pos * 2 + 1 });
        },
        .NonCaptureGroup => |grp| {
            try self.compileNode(alloc, grp.node);
        },
    }
}

/// Emits bytecode for supported postfix quantifiers.
fn compileRepeat(self: Compiler, alloc: std.mem.Allocator, rep: syntax.Repeat) ErrorSet!void {
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try self.emit(.Hold);

        const body_start = self.buffer.len();
        try self.compileNode(alloc, rep.node);

        _ = try self.emit(.{ .Jump = split_idx });

        const after = self.buffer.len();

        try self.patch(split_idx, .{
            .Split = .{
                .left = body_start,
                .right = after,
            },
        });
        return;
    }

    if (rep.min == 1 and rep.max == null) {
        const body_start = self.buffer.len();

        try self.compileNode(alloc, rep.node);

        _ = try self.emit(.{
            .Split = .{
                .left = body_start,
                .right = self.buffer.len() + 1,
            },
        });
        return;
    }

    if (rep.min == 0 and rep.max.? == 1) {
        const split_idx = try self.emit(.Hold);

        const body_start = self.buffer.len();
        try self.compileNode(alloc, rep.node);

        const after = self.buffer.len();

        try self.patch(split_idx, .{
            .Split = .{
                .left = body_start,
                .right = after,
            },
        });
        return;
    }
    return ErrorSet.InvalidRepeat;
}

fn compileBranch(self: Compiler, alloc: std.mem.Allocator, branch: syntax.Branch) ErrorSet!void {
    const split_idx = try self.emit(.Hold);

    const left_start = self.buffer.len();
    try self.compileNode(alloc, branch.left);

    const jump_idx = try self.emit(.Hold);

    const right_start = self.buffer.len();
    try self.compileNode(alloc, branch.right);

    const after = self.buffer.len();

    try self.patch(split_idx, .{
        .Split = .{
            .left = left_start,
            .right = right_start,
        },
    });

    try self.patch(jump_idx, .{
        .Jump = after,
    });
}

/// Consumes the AST produced by `Parser`, emits Instructions to the bytecode buffer
pub fn compile(self: Compiler, alloc: std.mem.Allocator, tree: *const syntax.Node) ErrorSet!void {
    _ = try self.emit(.{ .Save = 0 });
    _ = try self.compileNode(alloc, tree);
    _ = try self.emit(.{ .Save = 1 });
    _ = try self.emit(.Match);
}

test "Should compile a sequence of literals `abc`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(allocator, null);
    defer buffer.deinit();

    const tree = try ast_alloc.alloc(*syntax.Node, 3);
    const chars = [_]u21{ 'a', 'b', 'c' };
    for (chars, 0..) |ch, i| {
        const node = try ast_alloc.create(syntax.Node);
        node.* = .{ .Literal = .{ .value = ch } };
        tree[i] = node;
    }

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    const compiler = Compiler.init(&buffer, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), buffer.len());

    var instruction = try buffer.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    for (chars, 0..) |ch, i| {
        const pos = i + 1;
        instruction = try buffer.get(pos);
        try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Rune);
        try testing.expectEqual(@as(u21, ch), instruction.Rune.value);
    }

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    const last_inst = try buffer.get(5);
    try testing.expect(std.meta.activeTag(last_inst.*) == Instruction.Match);
}

test "Should compile an anchored lowercase character class repeat `^[a-z]*$`" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(allocator, null);
    defer buffer.deinit();

    const start = try ast_alloc.create(syntax.Node);
    start.* = .{ .StartAnchor = .{} };

    const ranges = try ast_alloc.alloc(syntax.RuneRange, 1);
    ranges[0] = .{
        .start = 'a',
        .end = 'z',
    };
    const chars = try ast_alloc.alloc(u21, 0);

    const class_node = try ast_alloc.create(syntax.Node);
    class_node.* = .{
        .CharClass = .{
            .ranges = ranges,
            .chars = chars,
            .negated = false,
        },
    };

    const repeat = try ast_alloc.create(syntax.Node);
    repeat.* = .{ .Repeat = .{
        .node = class_node,
        .min = 0,
        .max = null,
    } };

    const end = try ast_alloc.create(syntax.Node);
    end.* = .{ .EndAnchor = .{} };

    const tree = try ast_alloc.alloc(*syntax.Node, 3);
    tree[0] = start;
    tree[1] = repeat;
    tree[2] = end;

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    const compiler = Compiler.init(&buffer, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 8), buffer.len());

    var instruction = try buffer.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertStart);
    try testing.expect(!instruction.AssertStart.multiline);

    instruction = try buffer.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 3), instruction.Split.left);
    try testing.expectEqual(@as(usize, 5), instruction.Split.right);

    instruction = try buffer.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Class);
    try testing.expectEqual(false, instruction.Class.class.negated);
    try testing.expectEqual(@as(usize, 1), instruction.Class.class.ranges.len);
    try testing.expectEqual(@as(u21, 'a'), instruction.Class.class.ranges[0].start);
    try testing.expectEqual(@as(u21, 'z'), instruction.Class.class.ranges[0].end);

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Jump);
    try testing.expectEqual(@as(usize, 2), instruction.Jump);

    instruction = try buffer.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertEnd);

    instruction = try buffer.get(6);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try buffer.get(7);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile branching `a|b`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(allocator, null);
    defer buffer.deinit();

    const left = try ast_alloc.create(syntax.Node);
    left.* = .{ .Literal = .{ .value = 'a' } };
    const right = try ast_alloc.create(syntax.Node);
    right.* = .{ .Literal = .{ .value = 'b' } };

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .Branch = .{
            .left = left,
            .right = right,
        },
    };

    const compiler = Compiler.init(&buffer, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 7), buffer.len());

    var instruction = try buffer.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 2), instruction.Split.left);
    try testing.expectEqual(@as(usize, 4), instruction.Split.right);

    instruction = try buffer.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try buffer.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Jump);
    try testing.expectEqual(@as(usize, 5), instruction.Jump);

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'b'), instruction.Rune.value);

    instruction = try buffer.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try buffer.get(6);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile a capture group `(a)`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(allocator, null);
    defer buffer.deinit();

    const lit = try ast_alloc.create(syntax.Node);
    lit.* = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .CaptureGroup = .{
            .pos = 1,
            .node = lit,
        },
    };

    const compiler = Compiler.init(&buffer, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), buffer.len());

    var instruction = try buffer.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 2), instruction.Save);

    instruction = try buffer.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try buffer.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 3), instruction.Save);

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try buffer.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile an optional repeat `a?`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(allocator, null);
    defer buffer.deinit();

    const lit = try ast_alloc.create(syntax.Node);
    lit.* = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .Repeat = .{
            .node = lit,
            .min = 0,
            .max = 1,
        },
    };

    const compiler = Compiler.init(&buffer, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 5), buffer.len());

    var instruction = try buffer.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 2), instruction.Split.left);
    try testing.expectEqual(@as(usize, 3), instruction.Split.right);

    instruction = try buffer.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try buffer.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should apply pattern flags to emitted instructions" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var buffer = try InstructionSet.init(
        allocator,
        null,
    );
    defer buffer.deinit();

    const literal = try ast_alloc.create(syntax.Node);
    literal.* = .{
        .Literal = .{
            .value = 'A',
        },
    };

    const wildcard = try ast_alloc.create(syntax.Node);
    wildcard.* = .{
        .AnyChar = .{},
    };

    const start = try ast_alloc.create(syntax.Node);
    start.* = .{
        .StartAnchor = .{},
    };

    const end = try ast_alloc.create(syntax.Node);
    end.* = .{
        .EndAnchor = .{},
    };

    const nodes = try ast_alloc.alloc(
        *syntax.Node,
        4,
    );

    nodes[0] = start;
    nodes[1] = literal;
    nodes[2] = wildcard;
    nodes[3] = end;

    const root = try ast_alloc.create(syntax.Node);
    root.* = .{
        .Sequence = .{
            .nodes = nodes,
        },
    };

    const compiler = Compiler.init(
        &buffer,
        .{
            .ignore_case = true,
            .multiline = true,
            .dot_all = true,
        },
    );
    try compiler.compile(allocator, root);

    var instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertStart);
    try testing.expect(instruction.AssertStart.multiline);

    instruction = try buffer.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(
        @as(u21, 'A'),
        instruction.Rune.value,
    );
    try testing.expect(instruction.Rune.ignore_case);

    instruction = try buffer.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Any);
    try testing.expect(instruction.Any.dot_all);

    instruction = try buffer.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertEnd);
    try testing.expect(instruction.AssertEnd.multiline);
}

test "Should compile zero-width assertions" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();
    var buffer = try InstructionSet.init(
        allocator,
        null,
    );
    defer buffer.deinit();

    const node = try ast_alloc.create(syntax.Node);

    node.* = .{
        .Assertion = .{
            .typ = .word_bounds,
        },
    };

    const compiler = Compiler.init(&buffer, .{});

    try compiler.compile(allocator, node);
    try testing.expectEqual(@as(usize, 4), buffer.len());

    const instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Assert);
    try testing.expectEqual(syntax.AssertionType.word_bounds, instruction.Assert);
}

test "Should preserve preset character classes" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();
    var buffer = try Bytecode.InstructionSet.init(
        allocator,
        null,
    );
    defer buffer.deinit();

    const node = try ast_alloc.create(syntax.Node);
    var preset: syntax.PresetClassSet = .{};
    preset.insert(.digit);

    node.* = .{
        .CharClass = .{
            .ranges = &.{},
            .chars = &.{},
            .preset = preset,
        },
    };

    const compiler = Compiler.init(&buffer, .{});

    try compiler.compile(allocator, node);

    const instruction = try buffer.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Class);
    try testing.expect(instruction.Class.class.preset.contains(.digit));
    try testing.expect(!instruction.Class.class.negated_preset.contains(.digit));
}
