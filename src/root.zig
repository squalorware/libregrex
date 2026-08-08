const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const pattern = @import("./pattern.zig");
const bytecode = engine.bytecode;
const tokens = engine.tokens;
const SubOptions = types.opt_args.SubOptions;

pub const Pattern = pattern.Pattern;
pub const Match = types.Match;
pub const MatchList = types.MatchListBuffer;
pub const RegrexError = types.Error;

/// Compiles a regex `pattern_str` string for later use.
/// 
/// Returns a reusable `Pattern` handle which encapsulates compiled pattern
/// and exposes a basic public interface for the consumer.
/// 
/// `Pattern` owns the encapsulated bytecode buffer and so must be released with
/// `Pattern.deinit`.
/// 
/// Returns `RegrexError` on failure
pub fn compile(alloc: std.mem.Allocator, pattern_str: []const u8) RegrexError!*Pattern {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var token_list = try tokens.TokenListBuffer.init(alloc, null);
    defer token_list.deinit();

    const lexer = engine.Lexer.init(pattern_str);
    try lexer.tokenize(&token_list);

    var parser = engine.Parser.init(arena.allocator, token_list.items());
    const ast = try parser.parse();

    var bcode = try bytecode.BytecodeBuffer.init(alloc, null);
    defer bcode.deinit();

    const compiler = engine.Compiler.init(&bcode);
    try compiler.compile(alloc, ast);

    return try Pattern.init(
        alloc,
        pattern_str,
        &bcode,
        parser.group_count,
    );
}

/// Compiles the string `pattern_str` and searches the `input` string 
/// for the first location where the `pattern` matches.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// Returns:
/// - `Match` on success (owns heap-allocated `subgroups` list, 
/// should be explicitly released by caller with `Match.deinit(alloc)`);
/// - `null` if no match found;
/// - `RegrexError` on failure
pub fn match(alloc: std.mem.Allocator, pattern_str: []const u8, input: []const u8) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern_str);
    defer compiled.deinit();

    return try compiled.match(input);
}

/// Compiles the string `pattern_str` and looks for a match 
/// at the beginning of the `input` string.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// Returns:
/// - `Match` on success (owns heap-allocated `subgroups` list, 
/// should be explicitly released by caller with `Match.deinit(alloc)`);
/// - `null` if no match found;
/// - `RegrexError` on failure
pub fn search(alloc: std.mem.Allocator, pattern_str: []const u8, input: []const u8) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern_str);
    defer compiled.deinit();

    return try compiled.search(input);
}

/// Compiles the string `pattern_str` and collects 
/// all non-overlapping matches in the `input string`.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// Returns:
/// - `MatchList` on success (heap allocated, should be explicitly 
/// released by caller with `MatchList.deinit()`)
/// - `RegrexError` on failure
pub fn findAll(alloc: std.mem.Allocator, pattern_str: []const u8, input: []const u8) RegrexError!MatchList {
    const compiled: *Pattern = try compile(alloc, pattern_str);
    defer compiled.deinit();

    return try compiled.findAll(input);
}

/// Compiles the string `pattern_str` and searches for matches in the `input` string, 
/// then copies non-matching parts and replaces the matches with the `repl` string.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// `options.count` controls the number of matches to replace (default = 0)
/// 
/// Returns:
/// - `[]u8` on success (heap allocated, should be explicitly 
/// released by caller with `alloc.free(replaced)`)
/// - `RegrexError` on failure
pub fn sub(
    alloc: std.mem.Allocator,
    pattern_str: []const u8,
    input: []const u8,
    repl: []const u8,
    opts: SubOptions,
) RegrexError![]const u8 {
    const compiled: *Pattern = try compile(alloc, pattern_str);
    defer compiled.deinit();

    return try compiled.sub(input, repl, opts);
}