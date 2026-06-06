const testing = @import("std").testing;

pub const Rune = u21;

pub const TokenType = enum {
    CHAR,
    ESCAPED_CHAR,
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
    typ: TokenType,
    val: ?Rune,
    pos: usize = 0,
};

const MetaCharMapEntry = struct {
    rune: Rune,
    tokenType: TokenType,
};

pub const MetaCharMap = struct {
    pub const map = [_]MetaCharMapEntry{
        .{ .rune = '.', .tokenType = .DOT },
        .{ .rune = '^', .tokenType = .CARET },
        .{ .rune = '$', .tokenType = .DOLLAR },
        .{ .rune = '*', .tokenType = .STAR },
        .{ .rune = '+', .tokenType = .PLUS },
        .{ .rune = '?', .tokenType = .QUESTION },
        .{ .rune = '|', .tokenType = .PIPE },
        .{ .rune = '(', .tokenType = .LPAREN },
        .{ .rune = ')', .tokenType = .RPAREN },
        .{ .rune = '[', .tokenType = .LBRACKET },
        .{ .rune = ']', .tokenType = .RBRACKET },
        .{ .rune = '-', .tokenType = .DASH },
    };

    pub fn lookUp(r: Rune) ?TokenType {
        for (map) |entry| {
            if (entry.rune == r) {
                return entry.tokenType;
            }
        }
        return null;
    }
};

test "MetaCharMap lookUp" {
    const cases = [_]struct {
        input: Rune,
        expected: ?TokenType,
    }{
        .{ .input = '.', .expected = .DOT },
        .{ .input = '^', .expected = .CARET },
        .{ .input = '$', .expected = .DOLLAR },
        .{ .input = '*', .expected = .STAR },
        .{ .input = '+', .expected = .PLUS },
        .{ .input = '?', .expected = .QUESTION },
        .{ .input = '|', .expected = .PIPE },
        .{ .input = '(', .expected = .LPAREN },
        .{ .input = ')', .expected = .RPAREN },
        .{ .input = '[', .expected = .LBRACKET },
        .{ .input = ']', .expected = .RBRACKET },
        .{ .input = '-', .expected = .DASH },
        // Not a regex metacharacter
        .{ .input = 'a', .expected = null },
    };

    for (cases) |c| {
        const result = MetaCharMap.lookUp(c.input);
        try testing.expectEqual(c.expected, result);
    }
}
