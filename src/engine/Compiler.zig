//! AST-to-bytecode compiler.
//! 
//! Consumes the AST produced by parser and emits 
//! an `InstructionList` for the VM to execute.
const std = @import("std");
const RegrexError = @import("types").Error;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const Instruction = bytecode.Instruction;
const InstructionList = bytecode.InstructionList;

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

pub const Self = @This();

instructions: *InstructionList,

/// Initializes a compiler state and 
/// allocates bytecode dynamic buffer
pub fn init(il: *InstructionList) Self {
    return .{ .instructions = il };
}

/// Appends an `Instruction` and returns its bytecode index 
fn emit(self: Self, inst: Instruction) RegrexError!usize {
    const idx = self.instructions.len();
    try self.instructions.append(inst);

    return idx;
}

/// Replaces a previously emitted placeholder `Instruction`.
/// 
/// Used for forward jumps where the target address is unknown
/// until after compiling a branch or repeating body
fn patch(self: Self, idx: usize, inst: Instruction) void {
    try self.instructions.set(idx, inst);
}

/// Emit bytecode for an AST Node
fn compileNode(
    self: Self, 
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

/// Emits bytecode for supported postfix quantifiers.
/// 
/// The supported forms are:
/// - `*` (zero or more)
/// - `+` (one to more)
/// - `?` (zero to one)
/// 
/// Returns `RegrexError.InvalidRepeat` for unsupported repeat patterns.
fn compileRepeat(
    self: Self, 
    alloc: std.mem.Allocator, 
    rep: AST.Repeat
) RegrexError!void {
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try self.emit(undefined);

        const body_start = self.instructions.len();
        try self.compileNode(alloc, rep.node);

        _ = try self.emit(.{ .Jump = split_idx });

        const after = self.instructions.len();

        self.patch(split_idx, .{
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
fn compileBranch(
    self: Self, 
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
pub fn compile(
    self: Self, 
    alloc: std.mem.Allocator, 
    node: *const AST.Node
) RegrexError!void {
    try self.emit(.{ .Save = 0 });
    try self.compileNode(alloc, node);
    try self.emit(.{ .Save = 1 });
    try self.emit(.Match);
}
