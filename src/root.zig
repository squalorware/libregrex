const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const Bytecode = engine.Bytecode;
const tokens = engine.tokens;
const errors = types.errors;
const meta = types.meta;
const T_MergedStruct = meta.T_MergedStruct;

pub const LazyIterator = engine.LazyIterator;
pub const CompileFlags = types.CompileFlags;
pub const freeAllocated = types.meta.freeAllocated;
pub const Match = types.Match;
pub const Pattern = engine.Pattern;
pub const RegrexError = errors.ErrorSet;
pub const Span = types.Span;

pub const PatternSubOptions = engine.PatternSubOptions;
pub const SubOptions = T_MergedStruct(CompileFlags, PatternSubOptions);

/// Compiles regular expression string. 
/// Returns a pointer type that wraps the pattern buffer and exposes public interface
/// 
/// Accepts flags to modify pattern behaviour
pub fn compile(alloc: std.mem.Allocator, pattern: []const u8, flags: CompileFlags) RegrexError!*Pattern {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var token_list = try tokens.TokenListBuffer.init(alloc, .{});
    defer token_list.deinit();

    var lexer = engine.Lexer.init(pattern);
    try lexer.tokenize(&token_list);

    var parser = engine.Parser.init(arena.allocator(), token_list.items());
    const ast = try parser.parse();

    var bytecode = try Bytecode.InstructionSet.init(alloc, .{});
    defer bytecode.deinit();

    const compiler = engine.Compiler.init(&bytecode, flags);
    try compiler.compile(alloc, ast);

    return try Pattern.init(alloc, pattern, &bytecode, parser.group_count);
}

/// Returns the first match encountered at the beginning of the input
pub fn match(alloc: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: CompileFlags) RegrexError!?Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.match(input);
}

/// Returns the first match produced at any position within the input
pub fn search(alloc: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: CompileFlags) RegrexError!?Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.search(input);
}

/// Returns a slice containing all non-overlapping matches found in the input
/// 
/// The caller owns the slice and must explicitly release it
pub fn findAll(
    alloc: std.mem.Allocator, 
    pattern: []const u8, 
    input: []const u8, 
    flags: CompileFlags
) RegrexError![]Match {
    const regex: *Pattern = try compile(alloc, pattern, flags);
    defer regex.deinit();

    return try regex.findAll(input);
}


/// Copies the input string to a dynamic buffer, then substitutes all pattern matches with a replacement string
/// 
/// Returns the modified copy of the input. Returned slice is owned by caller and must be released
pub fn sub(
    alloc: std.mem.Allocator,
    pattern: []const u8,
    input: []const u8,
    repl: []const u8,
    option_set: SubOptions,
) RegrexError![]u8 {
    const regex: *Pattern = try compile(alloc, pattern, @as(CompileFlags, .{
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
