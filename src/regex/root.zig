const std = @import("std");
const types = @import("types");
const lexing = @import("./lexing/root.zig");
const parsing = @import("./parsing/root.zig");
const syntax = @import("./syntax.zig");
const comp = @import("./compiler.zig");
const opcodes = @import("./opcodes.zig");
const ErrorSet = types.errors.ErrorSet;
const Lexer = lexing.Lexer;
const Parser = parsing.Parser;
const Instruction = opcodes.Instruction; 

fn compileRepeat(alloc: std.mem.Allocator, compiler: *comp.Compiler, rep: syntax.Repeat) ErrorSet!void {
    // STAR quantifier
    if (rep.min == 0 and rep.max == null) {
        const split_idx = try compiler.emitSplit(0, 0);

        const body_start = compiler.code_buf.len();
        try compileNode(alloc, rep.node);

        _ = try compiler.emitJump(split_idx);

        const after = compiler.code_buf.len();

        compiler.patchSplit(split_idx, body_start, after);
        return;
    }

    // PLUS quantifier
    if (rep.min == 1 and rep.max == null) {
        const body_start = compiler.code_buf.len();

        try compileNode(alloc, rep.node);

        const split_idx = try compiler.emitSplit(
            body_start,
            0,
        );

        const after = compiler.code_buf.len();

        compiler.patchSplit(split_idx, body_start, after);
        return;
    }

    // QUESTION quantifier
    if (rep.min == 0 and rep.max.? == 1) {
        const split_idx = try compiler.emitSplit(0, 0);

        const body_start = compiler.code_buf.len();
        try compileNode(alloc, rep.node);

        const after = compiler.code_buf.len();

        compiler.patchSplit(split_idx, body_start, after);
        return;
    }

    return ErrorSet.InvalidRepeat;
}

fn compileBranch() void {}

fn compileNode() void {}

pub fn compile(alloc: std.mem.Allocator, pattern: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const allocator = arena.allocator();

    var lexer = lexing.Lexer.init();
    const token_list = try lexer.eval(allocator, pattern);

    var parser = parsing.Parser.init(allocator, token_list);
    defer parser.deinit();
    
    const ast = try parser.parse();

    var compiler = try comp.Compiler.init(alloc);
    defer compiler.deinit();

    _ = try compiler.emitSave(0);
    try compileNode(&compiler, ast);
    _ = try compiler.emitSave(1);
    _ = try compiler.emit(.Match);
}
