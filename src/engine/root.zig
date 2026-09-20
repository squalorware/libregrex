const testing = @import("std").testing;
const pattern = @import("./pattern.zig");
const iter = @import("./Iterator.zig");

pub const Bytecode = @import("./bytecode.zig");
pub const Compiler = @import("./Compiler.zig");
pub const lexing = @import("./lexing/root.zig");
pub const parsing = @import("./parsing/root.zig");
pub const VM = @import("./VM.zig");
pub const LazyIterator = iter.LazyIterator;
pub const Lexer = lexing.Lexer;
pub const Parser = parsing.Parser;
pub const PatternSubOptions = pattern.PatternSubOptions;
pub const Pattern = pattern.Pattern;
pub const syntax = parsing.syntax;

test {
    _ = @import("./Compiler.zig");
    _ = @import("./VM.zig");
    _ = @import("./lexing/tokens.zig");
    _ = @import("./lexing/escapes.zig");
    _ = @import("./lexing/root.zig");
    _ = @import("./parsing/root.zig");
    _ = @import("./parsing/char_classes.zig");
    _ = @import("./parsing/escapes.zig");
    _ = @import("./parsing/groups.zig");
}
