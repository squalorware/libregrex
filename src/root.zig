const std = @import("std");
const types = @import("types");
const regexp = @import("regexp");
// const engine = @import("engine");
// const Bytecode = engine.Bytecode;
const syntax = regexp.syntax;
const errors = types.errors;
const meta = types.meta;
const T_MergedStruct = meta.T_MergedStruct;

/// Generic destructor for any owned slice of type `T`. Accepts optional destructor callback for complex deinit logic
pub const free = types.meta.freeAlloc;
// /// Lazy iterator over matches. Initialized by `Pattern`, then ownership is transferred to caller.
// pub const FindIterator = engine.LazyIterator;
// /// Pattern behaviour modifiers. Can be inline as special characters in the pattern or passed to `compile` as an argument
// pub const Flags = engine.syntax.Flags;
// /// Data structure that stores the matching result as a buffer of byte offsets. Owned by caller.
pub const Match = types.Match;
/// Opaque type which encapsulates the compiled regex pattern and provides API. Owned by caller.
// pub const Pattern = engine.Pattern;
/// Error set used by the library
pub const RegrexError = errors.ErrorSet;
/// Byte offset within the input string. Represents match data (full match and capture groups).
///     Follows slice semantics: `.start` is inclusive; `.end` is exclusive.
pub const Span = types.Span;

// pub const PatternSubOptions = engine.PatternSubOptions;
// pub const SubOptions = T_MergedStruct(Flags, PatternSubOptions);

/// Compiles regular expression string and returns the compiled pattern
pub fn compile(gpa: std.mem.Allocator, pattern: []const u8, flags: syntax.Flags) RegrexError!void {
    // var arena = std.heap.ArenaAllocator.init(gpa);
    // defer arena.deinit();
    var ctx = try regexp.compilePattern(gpa, pattern, flags);
    defer ctx.free();
    // const gpa = arena.allocator();

    // var lexer = engine.Lexer.init();
    // const token_list = try lexer.eval(gpa, pattern);

    // var parser = engine.Parser.init(gpa, token_list);
    // defer parser.deinit();

    // const ast = try parser.parse();
    // const combined = flags.merge(parser.inlineFlags());

    // var prog = try Bytecode.InstructionSet.init(gpa, null);
    // defer prog.deinit();

    // const compiler = engine.Compiler.init(&prog, combined);
    // try compiler.compile(gpa, ast);

    // return try Pattern.init(gpa, pattern, &prog, parser.captures_count);
}

// /// Returns the first match encountered at the beginning of the input
// pub fn match(gpa: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError!?Match {
//     const regex: *Pattern = try compile(gpa, pattern, flags);
//     defer regex.deinit();

//     return try regex.match(input);
// }

// /// Returns the first match produced at any position within the input
// pub fn search(gpa: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError!?Match {
//     const regex: *Pattern = try compile(gpa, pattern, flags);
//     defer regex.deinit();

//     return try regex.search(input);
// }

// /// Returns a slice containing all non-overlapping matches found in the input. Caller owns returned value
// pub fn findAll(gpa: std.mem.Allocator, pattern: []const u8, input: []const u8, flags: Flags) RegrexError![]Match {
//     const regex: *Pattern = try compile(gpa, pattern, flags);
//     defer regex.deinit();

//     return try regex.findAll(input);
// }

// /// Copies the input string and replaces matches with `repl`;
// /// Optional `SubOptions.count` controls number of substitutions (default - 0 (replace all matches))
// ///
// /// Caller owns returned value
// pub fn sub(
//     gpa: std.mem.Allocator,
//     pattern: []const u8,
//     input: []const u8,
//     repl: []const u8,
//     option_set: SubOptions,
// ) RegrexError![]u8 {
//     const regex: *Pattern = try compile(gpa, pattern, @as(Flags, .{
//         .ignore_case = option_set.ignore_case,
//         .multiline = option_set.multiline,
//         .dot_all = option_set.dot_all,
//         ._padding = option_set._padding,
//     }));
//     defer regex.deinit();

//     return try regex.sub(input, repl, @as(PatternSubOptions, .{
//         .count = option_set.count,
//     }));
// }

// test {
//     _ = @import("types");
//     _ = @import("unicode");
//     _ = @import("engine");
// }
