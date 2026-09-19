const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const Bytecode = engine.Bytecode;
const tokens = engine.tokens;
const errors = types.errors;
const meta = types.meta;
const T_MergedStruct = meta.T_MergedStruct;

/// Lazy iterator over matches. Initialized by `Pattern`, then ownership is transferred to caller.
pub const LazyIterator = engine.LazyIterator;
/// Pattern behaviour modifiers. Can be inline as special characters in the pattern or passed to `compile` as an argument 
pub const Flags = engine.Flags;
/// Generic destructor for any owned slice of type `T`. Accepts optional destructor callback for complex deinit logic
pub const freeAlloc = types.meta.freeAlloc;
/// Data structure that stores the matching result as a buffer of byte offsets. Owned by caller.
pub const Match = types.Match;
/// Opaque type which encapsulates the compiled regex pattern and provides API. Owned by caller.
pub const Pattern = engine.Pattern;
/// Common parsing and compilation errors
pub const RegrexError = errors.ErrorSet;
/// Byte offset within the input string. Represents match data (full match and capture groups).
///     Follows slice semantics: `.start` is inclusive; `.end` is exclusive.
pub const Span = types.Span;

pub const PatternSubOptions = engine.PatternSubOptions;
pub const SubOptions = T_MergedStruct(Flags, PatternSubOptions);

/// Compiles regular expression string and returns the compiled pattern
pub fn compile(alloc: std.mem.Allocator, pattern: []const u8, flags: Flags) RegrexError!*Pattern {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var token_list = try tokens.TokenListBuffer.init(alloc, null);
    defer token_list.deinit();

    var lexer = engine.Lexer.init(pattern);
    try lexer.tokenize(&token_list);

    var parser = engine.Parser.init(arena.allocator(), token_list.items());
    defer parser.deinit();
    
    const ast = try parser.parse();
    const combined = flags.merge(parser.inlineFlags());

    var prog = try Bytecode.InstructionSet.init(alloc, null);
    defer prog.deinit();

    const compiler = engine.Compiler.init(&prog, combined);
    try compiler.compile(alloc, ast);

    return try Pattern.init(alloc, pattern, &prog, parser.group_count);
}

/// Returns the first match encountered at the beginning of the input
pub fn match(alloc: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError!?Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.match(input);
}

/// Returns the first match produced at any position within the input
pub fn search(alloc: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError!?Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.search(input);
}

/// Returns a slice containing all non-overlapping matches found in the input. Caller owns returned value
pub fn findAll(alloc: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError![]Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.findAll(input);
}

/// Copies the input string and replaces matches with `repl`;
/// Optional `SubOptions.count` controls number of substitutions (default - 0 (replace all matches))
///
/// Caller owns returned value
pub fn sub(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
    repl: []const u8,
    option_set: SubOptions,
) RegrexError![]u8 {
    const regex: *Pattern = try compile(alloc, pattern, @as(Flags, .{
        .ignore_case = option_set.ignore_case,
        .multiline = option_set.multiline,
        .dot_all = option_set.dot_all,
        ._padding = option_set._padding,
    }));
    defer regex.deinit();

    return try regex.sub(input, repl, @as(PatternSubOptions, .{
        .count = option_set.count,
    }));
}

test {
    _ = @import("types");
    _ = @import("unicode");
    _ = @import("engine");
}
