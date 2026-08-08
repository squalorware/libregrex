//! AST-to-bytecode compiler.
//! 
//! Consumes the AST produced by parser and emits 
//! an `InstructionList` for the VM to execute.
const std = @import("std");
const RegrexError = @import("types").Error;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const testing = std.testing;
const Instruction = bytecode.Instruction;
const BytecodeBuffer = bytecode.BytecodeBuffer;

/// Deep-copies a character class into bytecode memory.
/// 
/// Prevents bytecode from pointing into the temporary `Parser` AST arena
/// 
/// Returns `RegrexError.MemoryError` if failed to allocate memory on heap for copy
fn cloneCharClass(
    alloc: std.mem.Allocator, 
    cls: AST.CharClass
) RegrexError!AST.CharClass {
    const ranges = alloc.dupe(AST.CharRange, cls.ranges) catch {
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
        .negated = cls.negated,
    };
}

pub const Compiler = @This();

instructions: *BytecodeBuffer,

/// Initializes a compiler state and 
/// allocates bytecode dynamic buffer
pub fn init(inst_list: *BytecodeBuffer) Compiler {
    return .{ .instructions = inst_list };
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
            const owned = try cloneCharClass(alloc, cls);
            _ = try self.emit(.{ .Class = owned });
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
        const split_idx = try self.emit(undefined);

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
        const split_idx = try self.emit(undefined);

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
    const split_idx = try self.emit(undefined);

    const left_start = self.instructions.len();
    try self.compileNode(alloc, branch.left);

    const jump_idx = try self.emit(undefined);

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

    var inst_list = try bytecode.BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const tree = try ast_alloc.alloc(*AST.Node, 3);
    const chars = [_]u21 {'a', 'b', 'c'};
    for (chars, 0..) |ch, i| {
        const node = try ast_alloc.create(AST.Node);
        node = .{ .Literal = .{ .value = ch } };
        tree[i] = node;
    }

    const root = try ast_alloc.create(AST.Node);
    root = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    const compiler = Compiler.init(&inst_list);
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), inst_list.len());

    const first_inst = try inst_list.get(0);
    try testing.expect(first_inst == Instruction.Save);
    try testing.expectEqual(@as(usize, 0), first_inst.Save);

    for (chars, 0..) |ch, i| {
        const pos = i + 1;
        const inst = try inst_list.get(pos);
        try testing.expect(inst == Instruction.Rune);
        try testing.expectEqual(@as(u21, ch), inst.Rune);
    }

    const next_inst = try inst_list.get(4);
    try testing.expect(next_inst == Instruction.Save);
    try testing.expectEqual(@as(usize, 1), next_inst.Save);

    const last_inst = try inst_list.get(5);
    try testing.expect(last_inst == Instruction.Match);
}

test "Should compile an anchored lowercase character class repeat `^[a-z]*$`" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try bytecode.BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const start = try ast_alloc.create(AST.Node);
    start = .{ .StartAnchor = .{} };

    const ranges = try ast_alloc.alloc(AST.CharRange, 1);
    ranges[0] = .{
        .start = 'a',
        .end = 'z',
    };
    const chars = try ast_alloc.alloc(u21, 0);

    const class_node = try ast_alloc.create(AST.Node);
    class_node = .{
        .CharClass = .{
            .ranges = ranges,
            .chars = chars,
            .negated = false,
        },
    };

    const repeat = try ast_alloc.create(AST.Node);
    repeat = .{
        .Repeat = .{
            .node = class_node,
            .min = 0,
            .max = null,
        }
    };

    const end = try ast_alloc.create(AST.Node);
    end = .{ .EndAnchor = .{} };

    const tree = try ast_alloc.alloc(*AST.Node, 3);
    tree[0] = start;
    tree[1] = repeat;
    tree[2] = end;

    const root = try ast_alloc.create(AST.Node);
    root = .{
        .Sequence = .{
            .nodes = tree,
        },
    };

    const compiler = Compiler.init(&inst_list);
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 8), inst_list.len());

    const first_inst = try inst_list.get(0);
    try testing.expect(first_inst == .Save);
    try testing.expectEqual(@as(usize, 0), first_inst.Save);

    var next_inst: *Instruction = try inst_list.get(1);
    try testing.expect(next_inst == .AssertStart);

    next_inst = try inst_list.get(2);
    try testing.expect(next_inst == .Split);
    try testing.expectEqual(@as(usize, 3), next_inst.Split.first);
    try testing.expectEqual(@as(usize, 5), next_inst.Split.second);

    next_inst = try inst_list.get(3);
    try testing.expect(next_inst == .Class);
    try testing.expectEqual(false, next_inst.Class.negated);
    try testing.expectEqual(@as(usize, 1), next_inst.Class.ranges.len);
    try testing.expectEqual(@as(u21, 'a'), next_inst.Class.ranges[0].start);
    try testing.expectEqual(@as(u21, 'z'), next_inst.Class.ranges[0].end);

    next_inst = try inst_list.get(4);
    try testing.expect(next_inst == .Jump);
    try testing.expectEqual(@as(usize, 2), next_inst.Jump);

    next_inst = try inst_list.get(5);
    try testing.expect(next_inst == .AssertEnd);

    next_inst = try inst_list.get(6);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 1), next_inst.Save);

    next_inst = try inst_list.get(7);
    try testing.expect(next_inst == .Match);
}

test "Should compile branching `a|b`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try bytecode.BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const left = try ast_alloc.create(AST.Node);
    left = .{ .Literal = .{ .value = 'a' } };
    const right = try ast_alloc.create(AST.Node);
    right = .{ .Literal = .{ .value = 'b' } };

    const root = try ast_alloc.create(AST.Node);
    root = .{
        .Branch = .{
            .left = left,
            .right = right,
        },
    };

    const compiler = Compiler.init(&inst_list);
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 7), inst_list.len());

    const first_inst = try inst_list.get(0);
    try testing.expect(first_inst == .Save);
    try testing.expectEqual(@as(usize, 0), first_inst.Save);

    var next_inst = try inst_list.get(1);
    try testing.expect(next_inst == .Split);
    try testing.expectEqual(@as(usize, 2), next_inst.Split.first);
    try testing.expectEqual(@as(usize, 4), next_inst.Split.second);

    next_inst = try inst_list.get(2);
    try testing.expect(next_inst == .Rune);
    try testing.expectEqual(@as(u21, 'a'), next_inst.Rune);

    next_inst = try inst_list.get(3);
    try testing.expect(next_inst == .Jump);
    try testing.expectEqual(@as(usize, 5), next_inst.Jump);

    next_inst = try inst_list.get(4);
    try testing.expect(next_inst == .Rune);
    try testing.expectEqual(@as(u21, 'b'), next_inst.Rune);

    next_inst = try inst_list.get(5);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 1), next_inst.Save);

    next_inst = try inst_list.get(6);
    try testing.expect(next_inst == .Match);
}

test "Should compile a capture group `(a)`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try bytecode.BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const lit = try ast_alloc.create(AST.Node);
    lit = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(AST.Node);
    root = .{
        .CaptureGroup = .{
            .pos = 1,
            .node = lit,
        },
    };


    const compiler = Compiler.init(&inst_list);
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 6), inst_list.len());

    const first_inst = try inst_list.get(0);
    try testing.expect(first_inst == .Save);
    try testing.expectEqual(@as(usize, 0), first_inst.Save);

    var next_inst = try inst_list.get(1);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 2), next_inst.Save);

    next_inst = try inst_list.get(2);
    try testing.expect(next_inst == .Rune);
    try testing.expectEqual(@as(u21, 'a'), next_inst.Rune);

    next_inst = try inst_list.get(3);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 3), next_inst.Save);

    next_inst = try inst_list.get(4);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 1), next_inst.Save);

    next_inst = try inst_list.get(5);
    try testing.expect(next_inst == .Match);
}

test "Should compile an optional repeat `a?`" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const ast_alloc = arena.allocator();

    var inst_list = try bytecode.BytecodeBuffer.init(allocator, null);
    defer inst_list.deinit();

    const lit = try ast_alloc.create(AST.Node);
    lit = .{ .Literal = .{ .value = 'a' } };

    const root = try ast_alloc.create(AST.Node);
    root = .{
        .Repeat = .{
            .node = lit,
            .min = 0,
            .max = 1,
        },
    };

    const compiler = Compiler.init(&inst_list);
    try compiler.compile(allocator, root);

    try testing.expectEqual(@as(usize, 5), inst_list.len());

    const first_inst = try inst_list.get(0);
    try testing.expect(first_inst == .Save);
    try testing.expectEqual(@as(usize, 0), first_inst.Save);

    var next_inst = try inst_list.get(1);
    try testing.expect(next_inst == .Split);
    try testing.expectEqual(@as(usize, 2), next_inst.Split.first);
    try testing.expectEqual(@as(usize, 3), next_inst.Split.second);

    next_inst = try inst_list.get(2);
    try testing.expect(next_inst == .Rune);
    try testing.expectEqual(@as(u21, 'a'), next_inst.Rune);

    next_inst = try inst_list.get(3);
    try testing.expect(next_inst == .Save);
    try testing.expectEqual(@as(usize, 1), next_inst.Save);

    next_inst = try inst_list.get(4);
    try testing.expect(next_inst == .Match);
}
