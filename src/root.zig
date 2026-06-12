const std = @import("std");
const Compiler = @import("./core/Compiler.zig");
const Lexer = @import("./core/Lexer.zig");
const Parser = @import("./core/Parser.zig");
const Pattern = @import("./pattern.zig").Pattern;

pub fn _compile(
    alloc: std.mem.Allocator,
    pattern: []const u8,
) !*Pattern {
    var lexer = Lexer.init(pattern);
    const tokens = try lexer.tokenize(alloc);
    defer alloc.free(tokens);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var parser = Parser.init(arena.allocator(), tokens);
    const ast = try parser.parse();

    var compiler = Compiler.init(alloc);
    const opcodes = try compiler.compile(ast);
    errdefer Pattern.freeBytecode(alloc, opcodes);

    return try Pattern.init(
        alloc, 
        parser.group_count, 
        opcodes, 
        pattern
    );
}

/// Dummy placeholder function (temporary)
pub fn compile() void {}

test {
    _ = @import("./common/utils.zig");
    _ = @import("./core/Token.zig");
    _ = @import("./core/Lexer.zig");
    _ = @import("./core/Parser.zig");
    _ = @import("./core/Compiler.zig");
    _ = @import("./Match.zig");
}
