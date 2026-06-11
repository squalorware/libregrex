const std = @import("std");
const Compiler = @import("./compiler/root.zig");
const Lexer = @import("./compiler/lexer/root.zig");
const Parser = @import("./compiler/parser/root.zig");
const Regex = @import("./regex.zig");

pub fn _compile(
    alloc: std.mem.Allocator,
    pattern: []const u8,
) !Regex {
    var lexer = Lexer.init(pattern);
    const tokens = try lexer.tokenize(alloc);
    defer alloc.free(tokens);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var parser = Parser.init(arena.allocator(), tokens);
    const ast = try parser.parse();

    var compiler = Compiler.init(alloc);
    const opcodes = try compiler.compile(ast);

    return .{
        .alloc = alloc,
        .compiled = opcodes,
        .group_count = parser.group_count,
        .raw = pattern,
    };
}

/// Dummy placeholder function (temporary)
pub fn compile() void {}

test {
    _ = @import("./compiler/lexer/token.zig");
    _ = @import("./compiler/lexer/root.zig");
    _ = @import("./compiler/parser/root.zig");
    _ = @import("./compiler/root.zig");
}
