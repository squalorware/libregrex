const testing = @import("std").testing;
const pattern = @import("./pattern.zig");
const iter = @import("./Iterator.zig");

pub const Bytecode = @import("./bytecode.zig");
pub const tokens = @import("./tokens.zig");
pub const Compiler = @import("./Compiler.zig");
pub const LazyIterator = iter.LazyIterator;
pub const Lexer = @import("./Lexer.zig");
pub const parsing = @import("./parsing/root.zig");
pub const Flags = parsing.groups.Flags;
pub const Parser = parsing.Parser;
pub const VM = @import("./VM.zig");
pub const PatternSubOptions = pattern.PatternSubOptions;
pub const Pattern = pattern.Pattern;

test {
    _ = @import("./tokens.zig");
    _ = @import("./Lexer.zig");
    _ = @import("./Compiler.zig");
    _ = @import("./VM.zig");
    _ = @import("./parsing/char_classes.zig");
    _ = @import("./parsing/escapes.zig");
    _ = @import("./parsing/groups.zig");
}
