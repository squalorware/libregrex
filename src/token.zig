pub const Rune = u21;

pub const TokenType = enum {
    CHAR,
    DOT,
    CARET,
    DOLLAR,
    STAR,
    PLUS,
    QUESTION,
    PIPE,
    LPAREN,
    RPAREN,
    LBRACKET,
    RBRACKET,
    DASH,
    NEGATE,
    EOF,
};

pub const Token = struct {
    const Self = @This();

    typ: TokenType,
    val: Rune,
    pos: usize = 0,

    pub fn init(typ: TokenType, val: Rune, pos: usize) Self {
        return .{
            .typ = typ,
            .val = val,
            .pos = pos,
        };
    }
};
