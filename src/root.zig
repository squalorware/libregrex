const std = @import("std");
const Compiler = @import("./core/Compiler.zig");
const Lexer = @import("./core/Lexer.zig");
const Parser = @import("./core/Parser.zig");
const Regex = @import("./Regex.zig");

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
    _ = @import("./core/Token.zig");
    _ = @import("./core/Lexer.zig");
    _ = @import("./core/Parser.zig");
    _ = @import("./core/Compiler.zig");
    _ = @import("./Match.zig");
}
