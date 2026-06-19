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
    return try Pattern.init(
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
    options: struct {
        count: usize = 0,
    },
) RegrexError![]u8 {
    const compiled: *Pattern = try compile(alloc, pattern);
    defer compiled.deinit();

    return compiled.sub(repl, input, options);
}

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
}
