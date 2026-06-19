//! Regrex - a simple implementation of PCRE/Python-inspired regular expression engine.
//! 
//! Implements a full lifecycle of compiling a string regular expression pattern into
//! bytecode instructions executed by a simple backtracking virtual machine. 
//! 
//! Currently supports the most basic regular expression grammar. Provides functions
//! that allow both one-off regex operations with string pattern against a string input 
//! and ability to compile regex once and reuse compiled pattern until manually released.
const std = @import("std");
const Compiler = @import("./core/Compiler.zig");
const Lexer = @import("./core/Lexer.zig");
const Parser = @import("./core/Parser.zig");
const regexPattern = @import("./pattern.zig");
const freeCompiledBuffer = regexPattern.freeCompiledBuffer;
const SubOptions = regexPattern.SubOptions;

/// Library-specific error definitions
pub const RegrexError = @import("./common/errors.zig").RegrexError;
/// Representation of a result object returned by matching operations. 
/// Contains byte offsets of matches substringing the input string
pub const Match = @import("./Match.zig");
/// Opaque type encapsulating compiled regex pattern and exposing a public interface 
pub const Pattern = regexPattern.Pattern;

/// Compiles a regex pattern string for later use.
/// 
/// Returns a reusable `Pattern` handle which encapsulates compiled pattern
/// and exposes a basic public interface for the consumer.
/// 
/// `Pattern` owns the encapsulated bytecode buffer and so must be released with
/// `Pattern.deinit`.
/// 
/// Returns `RegrexError` on failure
pub fn compile(
    alloc: std.mem.Allocator,
    pattern: []const u8,
) RegrexError!*Pattern {
    // Perform lexical analysis on the pattern string and break it into a Token stream
    var lexer = Lexer.init(pattern);
    const tokens = try lexer.tokenize(alloc);
    defer alloc.free(tokens);
    
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    // Parse tokenized pattern and build an abstract syntax tree
    var parser = Parser.init(arena.allocator(), tokens);
    const ast = try parser.parse();

    // Compile the AST into an intermediate code representation
    var compiler = Compiler.init(alloc);
    const bytecode = try compiler.compile(ast);
    errdefer freeCompiledBuffer(alloc, bytecode);

    // Return an opaque public type that owns the compiled bytecode 
    // and exposes the reusable matching interface.
    return Pattern.init(
        alloc, 
        parser.group_count, 
        bytecode, 
        pattern
    );
}

/// Searches the `input` string for the first location where the `pattern` matches.
/// 
/// One-shot function - compiles the string pattern internally 
/// and destroys the `*Pattern` object at execution end.
/// 
/// Returns:
/// - `Match` on success (owns heap-allocated `subgroups` list, 
/// should be explicitly released by caller with `Match.deinit(alloc)`);
/// - `null` if no match found;
/// - `RegrexError` on failure
pub fn search(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8
) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.search(input);
}

/// Attempts to match a `pattern` at the beginning of the `input` string.
/// 
/// One-shot function - compiles the string pattern internally 
/// and destroys the `*Pattern` object at execution end.
/// 
/// Returns:
/// - `Match` on success (owns heap-allocated `subgroups` list, 
/// should be explicitly released by caller with `Match.deinit(alloc)`);
/// - `null` if no match found;
/// - `RegrexError` on failure
pub fn match(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.match(input);
}

/// Collects all non-overlapping matches in the `input string`.
/// 
/// One-shot function - compiles the string pattern internally 
/// and destroys the `*Pattern` object at execution end.
/// 
/// Returns:
/// - `[]Match` on success (heap allocated, should be explicitly 
/// released by caller with `Match.free(alloc, matches)`)
/// - `RegrexError` on failure
pub fn findAll(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
) RegrexError![]Match {
    const compiled: *Pattern = try compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.findAll(input);
}

/// Searches for matches in the `input` string, then copies non-matching parts
/// and replaces the matches with the `repl` string.
/// 
/// One-shot function - compiles the string pattern internally 
/// and destroys the `*Pattern` object at execution end.
/// 
/// `options.count` controls the number of matches to replace (default = 0)
/// 
/// Returns:
/// - `[]u8` on success (heap allocated, should be explicitly 
/// released by caller with `alloc.free(replaced)`)
/// - `RegrexError` on failure
pub fn sub(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    repl: []const u8,
    input: []const u8,
    options: SubOptions,
) RegrexError![]u8 {
    const compiled: *Pattern = try compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.sub(repl, input, options);
}

const testing = std.testing;

test {
    _ = @import("./common/types.zig");
    _ = @import("./common/utils.zig");
    _ = @import("./core/Token.zig");
    _ = @import("./core/Lexer.zig");
    _ = @import("./core/Parser.zig");
    _ = @import("./core/Compiler.zig");
    _ = @import("./Match.zig");
    _ = @import("./vm.zig");
    _ = @import("./pattern.zig");
    _ = @import("./extern.zig");
}

test "root.compile() should return a reusable *Pattern" {
    const allocator = testing.allocator;

    const pattern = try compile(allocator, "^[a-z]*$");
    defer pattern.deinit();

    var result = try (pattern.match("abc")) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("abc", result.full());

    const no_match = try pattern.match("abc1");
    try testing.expect(no_match == null);
}

test "root.match() should try to match only at the input start" {
    const allocator = testing.allocator;

    var result = (try match(
        allocator,
        "[0-9]+",
        "420 kek",
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.full());

    const no_match = try match(
        allocator, 
        "[0-9]+", 
        "lol 420 kek"
    );
    try testing.expect(no_match == null);
}

test "root.search() should return first match no matter its position in input" {
    const allocator = testing.allocator;

    var result = (try search(
        allocator,
        "[0-9]+",
        "lol 420 kek",
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "root.search() should support Unicode literal matching" {
    const allocator = testing.allocator;

    var result = (try search(
        allocator,
        "う",
        "hうй",
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("う", result.full());
}

test "root.findAll() should return all non-overlapping matches" {
    const allocator = testing.allocator;

    const matches = try findAll(
        allocator,
        "[0-9]+",
        "lol 420 kek 69",
    );
    defer Match.free(allocator, matches);

    try testing.expectEqual(@as(usize, 2), matches.len);

    try testing.expectEqualStrings("420", matches[0].full());
    try testing.expectEqual(@as(usize, 4), try matches[0].start(0));
    try testing.expectEqual(@as(usize, 7), try matches[0].end(0));

    try testing.expectEqualStrings("69", matches[1].full());
    try testing.expectEqual(@as(usize, 12), try matches[1].start(0));
    try testing.expectEqual(@as(usize, 14), try matches[1].end(0));
}

test "root.sub() replaces all occurences matching pattern" {
    const allocator = testing.allocator;

    const result = try sub(
        allocator,
        "[0-9]+",
        "SIXSEVEN",
        "lol 420 kek 69",
        .{}
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek SIXSEVEN", result);
}

test "root.sub() acknowledges option.count and replaces exact number of occurences" {
    const allocator = testing.allocator;

    const result = try sub(
        allocator,
        "[0-9]+",
        "SIXSEVEN",
        "lol 67 kek 420",
        .{ .count = 1 },
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek 420", result);
}

test "root.sub() replaces all occurences and safely ignores rest if options.count is greater than actual matches count" {
    const allocator = testing.allocator;

    const result = try sub(
        allocator,
        "[0-9]+",
        "SIXSEVEN",
        "lol 67 kek 420",
        .{ .count = 67 },
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek SIXSEVEN", result); 
}
