//! AST-to-bytecode compiler.
//! 
//! Consumes the AST produced by parser and emits 
//! an `InstructionList` for the VM to execute.
const std = @import("std");
const types = @import("types");
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const testing = std.testing;
const Instruction = bytecode.Instruction;
const BytecodeBuffer = bytecode.BytecodeBuffer;
const RegrexError = types.Error;

/// Deep-copies a character class into bytecode memory.
/// 
/// Prevents bytecode from pointing into the temporary `Parser` AST arena
/// 
/// Returns `RegrexError.MemoryError` if failed to allocate memory on heap for copy
fn cloneCharClass(
    alloc: std.mem.Allocator, 
    cls: AST.CharClass
) RegrexError!AST.CharClass {
    const ranges = alloc.dupe(AST.RuneRange, cls.ranges) catch {
        return RegrexError.MemoryError;
    };
    errdefer alloc.free(ranges);

    const chars = alloc.dupe(u21, cls.chars) catch {
        return RegrexError.MemoryError;
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

/// Pattern behaviour modifiers
pub const Flags = packed struct(u8) {
    /// Case-insensitive matching
    ignore_case: bool = false,
    /// Interpret `^` and `$` as marking start and end
    /// of a single line instead of the whole input
    multiline: bool = false,
    /// Wildcards match newline characters as well
    dot_all: bool = false,
    _padding: u5 = 0,
};

pub const Compiler = @This();

instructions: *BytecodeBuffer,
flags: Flags,

/// Initializes a compiler state and 
/// allocates bytecode dynamic buffer
pub fn init(inst_list: *BytecodeBuffer, flags: Flags) Compiler {
    return .{ .instructions = inst_list, .flags = flags };
}

/// Appends an `Instruction` and returns its bytecode index 
fn emit(self: Compiler, inst: Instruction) RegrexError!usize {
    const idx = self.instructions.len();
    try self.instructions.append(inst);

    return idx;
}

/// Replaces a previously emitted placeholder `Instruction`.
/// 
/// Used for forward jumps where the target address is unknown
/// until after compiling a branch or repeating body
fn patch(self: Compiler, idx: usize, inst: Instruction) RegrexError!void {
    try self.instructions.set(idx, inst);
}

/// Emit bytecode for an AST Node
fn compileNode(
    self: Compiler, 
    alloc: std.mem.Allocator, 
    node: *const AST.Node
) RegrexError!void {
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
            _ = try self.emit(.{
                .Any = .{
                    .dot_all = self.flags.dot_all,
                }
            });
        },
        .StartAnchor => {
            _ = try self.emit(.{
                .AssertStart = .{
                    .multiline = self.flags.multiline,
                },
            });
        },
        .EndAnchor => {
            _ =try self.emit(.{
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
            for (seq.nodes) |child| {
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
/// 
/// The supported forms are:
/// - `*` (zero or more)
/// - `+` (one to more)
/// - `?` (zero to one)
/// 
/// Returns `RegrexError.InvalidRepeat` for unsupported repeat patterns.
fn compileRepeat(
    self: Compiler, 
    alloc: std.mem.Allocator, 
    rep: AST.Repeat
) RegrexError!void {
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try self.emit(.Hold);

        const body_start = self.instructions.len();
        try self.compileNode(alloc, rep.node);

        _ = try self.emit(.{ .Jump = split_idx });

        const after = self.instructions.len();

        try self.patch(split_idx, .{
            .Split = .{
                .first = body_start,
                .second = after,
            },
        });
        return;
    }

    if (rep.min == 1 and rep.max == null) {
        const body_start = self.instructions.len();

        try self.compileNode(alloc, rep.node);

        _ = try self.emit(.{
            .Split = .{
                .first = body_start,
                .second = self.instructions.len() + 1,
            },
        });
        return;
    }

    if (rep.min == 0 and rep.max.? == 1) {
        const split_idx = try self.emit(.Hold);

        const body_start = self.instructions.len();
        try self.compileNode(alloc, rep.node);

        const after = self.instructions.len();

        try self.patch(split_idx, .{
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
fn compileBranch(
    self: Compiler, 
    alloc: std.mem.Allocator,
    branch: AST.Branch
) RegrexError!void {
    const split_idx = try self.emit(.Hold);

    const left_start = self.instructions.len();
    try self.compileNode(alloc, branch.left);

    const jump_idx = try self.emit(.Hold);

    const right_start = self.instructions.len();
    try self.compileNode(alloc, branch.right);

    const after = self.instructions.len();

    try self.patch(split_idx, .{
        .Split = .{
            .first = left_start,
            .second = right_start,
        },
    });

    try self.patch(jump_idx, .{
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
pub fn compile(
    self: Compiler, 
    alloc: std.mem.Allocator, 
    node: *const AST.Node
) RegrexError!void {
    _ = try self.emit(.{ .Save = 0 });
    _ = try self.compileNode(alloc, node);
    _ = try self.emit(.{ .Save = 1 });
    _ = try self.emit(.Match);
}

test "Should compile a sequence of literals `abc`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const tree = try ast_alloc.alloc(*AST.Node, 3);
    const chars = [_]u21 {'a', 'b', 'c'};
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

    const compiler = Compiler.init(&inst_list, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), inst_list.len());

    var instruction = try inst_list.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    for (chars, 0..) |ch, i| {
        const pos = i + 1;
        instruction = try inst_list.get(pos);
        try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Rune);
        try testing.expectEqual(@as(u21, ch), instruction.Rune.value);
    }

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == Instruction.Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    const last_inst = try inst_list.get(5);
    try testing.expect(std.meta.activeTag(last_inst.*) == Instruction.Match);
}

test "Should compile an anchored lowercase character class repeat `^[a-z]*$`" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const start = try ast_alloc.create(AST.Node);
    start.* = .{ .StartAnchor = .{} };

    const ranges = try ast_alloc.alloc(AST.RuneRange, 1);
    ranges[0] = .{
        .start = 'a',
        .end = 'z',
    };
    const chars = try ast_alloc.alloc(u21, 0);

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

    const compiler = Compiler.init(&inst_list, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 8), inst_list.len());

    var instruction = try inst_list.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertStart);
    try testing.expect(!instruction.AssertStart.multiline);

    instruction = try inst_list.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 3), instruction.Split.first);
    try testing.expectEqual(@as(usize, 5), instruction.Split.second);

    instruction = try inst_list.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Class);
    try testing.expectEqual(false, instruction.Class.class.negated);
    try testing.expectEqual(@as(usize, 1), instruction.Class.class.ranges.len);
    try testing.expectEqual(@as(u21, 'a'), instruction.Class.class.ranges[0].start);
    try testing.expectEqual(@as(u21, 'z'), instruction.Class.class.ranges[0].end);

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Jump);
    try testing.expectEqual(@as(usize, 2), instruction.Jump);

    instruction = try inst_list.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertEnd);

    instruction = try inst_list.get(6);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try inst_list.get(7);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile branching `a|b`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

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

    const compiler = Compiler.init(&inst_list, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 7), inst_list.len());

    var instruction = try inst_list.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 2), instruction.Split.first);
    try testing.expectEqual(@as(usize, 4), instruction.Split.second);

    instruction = try inst_list.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try inst_list.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Jump);
    try testing.expectEqual(@as(usize, 5), instruction.Jump);

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'b'), instruction.Rune.value);

    instruction = try inst_list.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try inst_list.get(6);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile a capture group `(a)`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const lit = try ast_alloc.create(AST.Node);
    lit.* = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .CaptureGroup = .{
            .pos = 1,
            .node = lit,
        },
    };

    const compiler = Compiler.init(&inst_list, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), inst_list.len());

    var instruction = try inst_list.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 2), instruction.Save);

    instruction = try inst_list.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try inst_list.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 3), instruction.Save);

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try inst_list.get(5);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should compile an optional repeat `a?`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

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

    const compiler = Compiler.init(&inst_list, .{});
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 5), inst_list.len());

    var instruction = try inst_list.get(0);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 0), instruction.Save);

    instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Split);
    try testing.expectEqual(@as(usize, 2), instruction.Split.first);
    try testing.expectEqual(@as(usize, 3), instruction.Split.second);

    instruction = try inst_list.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(@as(u21, 'a'), instruction.Rune.value);

    instruction = try inst_list.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Save);
    try testing.expectEqual(@as(usize, 1), instruction.Save);

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .Match);
}

test "Should apply pattern flags to emitted instructions" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try BytecodeBuffer.init(
        allocator,
        null,
    );
    defer inst_list.deinit();

    const literal = try ast_alloc.create(AST.Node);
    literal.* = .{
        .Literal = .{
            .value = 'A',
        },
    };

    const wildcard = try ast_alloc.create(AST.Node);
    wildcard.* = .{
        .AnyChar = .{},
    };

    const start = try ast_alloc.create(AST.Node);
    start.* = .{
        .StartAnchor = .{},
    };

    const end = try ast_alloc.create(AST.Node);
    end.* = .{
        .EndAnchor = .{},
    };

    const nodes = try ast_alloc.alloc(
        *AST.Node,
        4,
    );

    nodes[0] = start;
    nodes[1] = literal;
    nodes[2] = wildcard;
    nodes[3] = end;

    const root = try ast_alloc.create(AST.Node);
    root.* = .{
        .Sequence = .{
            .nodes = nodes,
        },
    };

    const compiler = Compiler.init(
        &inst_list,
        .{
            .ignore_case = true,
            .multiline = true,
            .dot_all = true,
        },
    );
    try compiler.compile(allocator,root);

    var instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertStart);
    try testing.expect(instruction.AssertStart.multiline);

    instruction = try inst_list.get(2);
    try testing.expect(std.meta.activeTag(instruction.*) == .Rune);
    try testing.expectEqual(
        @as(u21, 'A'),
        instruction.Rune.value,
    );
    try testing.expect(instruction.Rune.ignore_case);

    instruction = try inst_list.get(3);
    try testing.expect(std.meta.activeTag(instruction.*) == .Any);
    try testing.expect(instruction.Any.dot_all);

    instruction = try inst_list.get(4);
    try testing.expect(std.meta.activeTag(instruction.*) == .AssertEnd);
    try testing.expect(instruction.AssertEnd.multiline);
}

test "Should compile zero-width assertions" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();
    var inst_list = try BytecodeBuffer.init(
        allocator,
        null,
    );
    defer inst_list.deinit();

    const node = try ast_alloc.create(AST.Node);

    node.* = .{
        .Assertion = .{
            .typ = .word_bounds,
        },
    };

    const compiler = Compiler.init(&inst_list, .{});

    try compiler.compile(allocator,node);
    try testing.expectEqual(@as(usize, 4),inst_list.len());

    const instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Assert);
    try testing.expectEqual(AST.AssertionType.word_bounds,instruction.Assert);
}

test "Should preserve preset character classes" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();
    var inst_list = try bytecode.BytecodeBuffer.init(
        allocator,
        null,
    );
    defer inst_list.deinit();

    const node = try ast_alloc.create(AST.Node);
    var preset: AST.PresetClassSet = .{};
    preset.insert(.digit);

    node.* = .{
        .CharClass = .{
            .ranges = &.{},
            .chars = &.{},
            .preset = preset,
        },
    };

    const compiler = Compiler.init(&inst_list, .{});

    try compiler.compile(allocator, node);

    const instruction = try inst_list.get(1);
    try testing.expect(std.meta.activeTag(instruction.*) == .Class);
    try testing.expect(instruction.Class.class.preset.contains(.digit));
    try testing.expect(!instruction.Class.class.negated_preset.contains(.digit));
}
