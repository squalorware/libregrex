const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const bytecode = engine.bytecode;
const tokens = engine.tokens;
const MergedStruct = types.meta.MergedStruct;

pub const Flags = engine.Compiler.Flags;
pub const Match = types.Match;
pub const MatchList = types.MatchListBuffer;
pub const Pattern = engine.Pattern;
pub const PatternSubOptions = engine.PatternSubOptions;
pub const RegrexError = types.Error;
/// `Flags` and `PatternSubOptions` types merged into a single structure
pub const SubOptions = MergedStruct(Flags, PatternSubOptions);

/// Compiles a regex `pattern` string for later use. Accepts `Flags` that modify the behaviour.
///
/// Default flags all set to `false`. If the default behaviour is preferred, just pass an empty
/// structure literal
///
/// Returns a reusable `Pattern` handle which encapsulates compiled pattern
/// and exposes a basic public interface for the consumer.
/// 
/// `Pattern` owns the encapsulated bytecode buffer and so must be released with
/// `Pattern.deinit`.
/// 
/// Returns `RegrexError` on failure
pub fn compile(alloc: std.mem.Allocator, pattern: []const u8, flags: Flags) RegrexError!*Pattern {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var token_list = try tokens.TokenListBuffer.init(alloc, null);
    defer token_list.deinit();

    var lexer = engine.Lexer.init(pattern);
    try lexer.tokenize(&token_list);

    var parser = engine.Parser.init(arena.allocator(), token_list.items());
    const ast = try parser.parse();

    var bcode = try bytecode.BytecodeBuffer.init(alloc, null);
    defer bcode.deinit();

    const compiler = engine.Compiler.init(&bcode, flags);
    try compiler.compile(alloc, ast);

    return try Pattern.init(
        alloc,
        pattern,
        &bcode,
        parser.group_count,
    );
}

/// Compiles the string `pattern` and searches the `input` string
/// for the first location where the `pattern` matches.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
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
    flags: Flags
) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern, flags);
    defer compiled.deinit();

    return try compiled.match(input);
}

/// Compiles the string `pattern` and looks for a match
/// at the beginning of the `input` string.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// Returns:
/// - `Match` on success (owns heap-allocated `subgroups` list, 
/// should be explicitly released by caller with `Match.deinit(alloc)`);
/// - `null` if no match found;
/// - `RegrexError` on failure
pub fn search(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
    flags: Flags
) RegrexError!?Match {
    const compiled: *Pattern = try compile(alloc, pattern, flags);
    defer compiled.deinit();

    return try compiled.search(input);
}

/// Compiles the string `pattern` and collects
/// all non-overlapping matches in the `input string`.
/// 
/// Compiled `*Pattern` object is automatically destroyed at execution end.
/// 
/// Returns:
/// - `MatchList` on success (heap allocated, should be explicitly 
/// released by caller with `MatchList.deinit()`)
/// - `RegrexError` on failure
pub fn findAll(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
    flags: Flags
) RegrexError!MatchList {
    const compiled: *Pattern = try compile(alloc, pattern, flags);
    defer compiled.deinit();

    return try compiled.findAll(input);
}

/// Compiles the string `pattern` and searches for matches in the `input` string,
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
    pattern: []const u8,
    input: []const u8,
    repl: []const u8,
    option_set: SubOptions,
) RegrexError![]const u8 {
    const compiled: *Pattern = try compile(alloc, pattern, @as(Flags, .{
        .ignore_case = option_set.ignore_case,
        .multiline = option_set.multiline,
        .dot_all = option_set.dot_all,
        ._padding = option_set._padding,
    }));
    defer compiled.deinit();

    return try compiled.sub(input, repl, @as(PatternSubOptions, .{
        .count = option_set.count,
    }));
}

test {
    _ = @import("types");
    _ = @import("unicode");
    _ = @import("engine");
}
