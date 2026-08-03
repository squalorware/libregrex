const std = @import("std");
const RegrexError = @import("types").Error;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");
const tokens = @import("./tokens.zig");
const Instruction = bytecode.Instruction;
const InstructionList = bytecode.InstructionList;
const TokenList = tokens.TokenList;
pub const Token = tokens.Token;
pub const Lexer = @import("./Lexer.zig");
pub const Parser = @import("./Parser.zig");
pub const Compiler = @import("./Compiler.zig");
pub const VM = @import("./VM.zig");

pub fn initVM(alloc: std.mem.Allocator, pattern: []const u8, inst_list: *InstructionList) RegrexError!VM {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var token_list = TokenList.init(alloc);
    defer token_list.deinit();

    const lexer = Lexer.init(pattern);
    try lexer.tokenize(&token_list);

    var parser = Parser.init(arena.allocator, token_list.items());
    const ast = try parser.parse();

    const compiler = Compiler.init(inst_list);
    try compiler.compile(alloc, ast);

    return try VM.init(alloc, parser.group_count);
}
