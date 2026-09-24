const std = @import("std");
const types = @import("types");
const bytecode = @import("./bytecode/root.zig");
const compiler = @import("./compiler.zig");
const states = @import("./states.zig");
const lexing = @import("./lexing/root.zig");
const Parser = @import("./parsing/Parser.zig").Parser;
const ErrorSet = types.errors.ErrorSet;
const Lexer = lexing.Lexer;
const Token = lexing.Token;
const CompileBuffers = states.CompileBuffers;

pub const syntax = @import("./syntax.zig");
pub const CompileOutput = states.CompileOutput;
pub const ParserOutput = states.ParserOutput;

fn tokenize(alloc: std.mem.Allocator, input: []const u8) ErrorSet![]Token {
    var lexer = Lexer.init();
    return try lexer.eval(alloc, input);
}

fn buildSyntaxTree(alloc: std.mem.Allocator, tokens: []Token) ErrorSet!ParserOutput {
    var parser = Parser.init(alloc, tokens);
    defer parser.deinit();

    const node = try parser.parse();
    return ParserOutput{
        .syntax_tree = node,
        .inline_flags = parser.inlineFlags(),
        .captures_count = parser.captures_count,
    };
}

fn emitBytecode(alloc: std.mem.Allocator, parsed: ParserOutput, flags: syntax.Flags) ErrorSet!CompileOutput {
    const combined_flags = flags.merge(parsed.inline_flags);

    var buffers = try CompileBuffers.init(alloc, combined_flags);
    defer buffers.deinit();

    _ = try bytecode.emit(&buffers, .Save, 0);
    try compiler.compileNode(&buffers, parsed.syntax_tree);
    _ = try bytecode.emit(&buffers, .Save, 1);
    _ = try bytecode.emit(&buffers, .Match, null);

    return CompileOutput{
        .prog = try buffers.prog.toOwnedSlice(),
        .classes = try buffers.classes.toOwnedSlice(),
        .captures_count = parsed.captures_count,
    };
}

pub fn compilePattern(alloc: std.mem.Allocator, pattern: []const u8, flags: syntax.Flags) ErrorSet!CompileOutput {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const allocator = arena.allocator();

    const tokens = try tokenize(allocator, pattern);
    const parsed = try buildSyntaxTree(allocator, tokens);

    return try emitBytecode(alloc, parsed, flags);
}

test {
    _ = @import("./lexing/tokens.zig");
    _ = @import("./lexing/escapes.zig");
    _ = @import("./lexing/root.zig");
    _ = @import("./parsing/root.zig");
    _ = @import("./parsing/char_classes.zig");
    _ = @import("./parsing/escapes.zig");
    _ = @import("./parsing/groups.zig");
    _ = @import("./bytecode/opcodes.zig");
    _ = @import("./bytecode/operands.zig");
    _ = @import("./bytecode/root.zig");
    _ = @import("./compiler.zig");
    _ = @import("./states.zig");
    _ = @import("./syntax.zig");
}
