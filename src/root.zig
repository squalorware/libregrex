const std = @import("std");
const Compiler = @import("./core/Compiler.zig");
const Lexer = @import("./core/Lexer.zig");
const Parser = @import("./core/Parser.zig");
const PatternModule = @import("./pattern.zig");
const freeBytecode = PatternModule.freeBytecode;
pub const Match = @import("./Match.zig");
pub const Pattern = PatternModule.Pattern;

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
    const bytecode = try compiler.compile(ast);
    errdefer freeBytecode(alloc, bytecode);

    return try Pattern.init(
        alloc, 
        parser.group_count, 
        bytecode, 
        pattern
    );
}

pub fn search(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8
) !?Match {
    const compiled: *Pattern = try _compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.search(input);
}

pub fn match(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
) !?Match {
    const compiled: *Pattern = try _compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.match(input);
}

pub fn findAll(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
) ![]Match {
    const compiled: *Pattern = try _compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.findAll(input);
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
