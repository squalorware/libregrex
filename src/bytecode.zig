const AST = @import("ast.zig");
const Rune = @import("types.zig").Rune;

pub const Instruction = union(enum) {
    Rune: Rune,
    Any,
    Class: AST.CharClass,
    AssertStart,
    AssertEnd,
    Save: usize,
    Split: Split,
    Jump: usize,
    Match,
};

pub const Split = struct {
    first: usize,
    second: usize,
};
