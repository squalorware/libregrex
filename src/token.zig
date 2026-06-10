
const testing = @import("std").testing;
const Rune = @import("types.zig").Rune;

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
    EOF,
};

pub const Token = @This();

typ: TokenType,
val: ?Rune,
pos: usize = 0,

pub fn mapRuneToTokenType(rune: Rune) ?TokenType {
    return switch (rune) {
        '.' => .DOT,
        '^' => .CARET,
        '$' => .DOLLAR,
        '*' => .STAR,
        '+' => .PLUS,
        '?' => .QUESTION,
        '|' => .PIPE,
        '(' => .LPAREN,
        ')' => .RPAREN,
        '[' => .LBRACKET,
        ']' => .RBRACKET,
        '-' => .DASH,
        else => null,
    };
}

test "Should map a character to corresponding token type" {
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
        const result = mapRuneToTokenType(c.input);
        try testing.expectEqual(c.expected, result);
    }
}

