const std = @import("std");
const Rune = @import("unicode").Rune;
const ErrorSet = @import("types").errors.ErrorSet;
const isReserved = @import("./escapes.zig").isReserved;
const testing = std.testing;

pub const TokenId = enum {
    /// A literal unescaped Unicode code point
    CHAR,
    /// Escaped Unicode code point (treated as a literal after backslash)
    /// or Unicode character class or assertion
    ESCAPED_CHAR,
    /// `.` Wildcard
    DOT,
    /// `,` Range delimiter
    COMMA,
    /// `^` Start anchor or character class negation
    CARET,
    /// `$` End anchor
    DOLLAR,
    /// `*` 'Zero or more' quantifier
    STAR,
    /// `+` 'One or more' quantifier
    PLUS,
    /// `?` 'Zero or one' quantifier or non-capture group marker or inline flag marker
    QUESTION,
    /// `|` Branching operator
    PIPE,
    /// `(` Opening group delimiter
    LPAREN,
    /// `)` Closing group delimiter
    RPAREN,
    /// `[` Opening character-class (e.g. `[a-z]`) delimiter
    LBRACKET,
    /// `]` Closing character-class delimiter
    RBRACKET,
    /// `{` Opening repeat delimiter
    LBRACE,
    /// `}` Closing repeat delimiter
    RBRACE,
    /// `-` Character-class range separator
    DASH,
    /// Pattern end sentinel
    EOP,
};

/// Instance of Token
///
/// Holds corresponding character from input and its position within it
pub const Token = struct {
    id: TokenId,
    lexeme: ?Rune,
    pos: usize = 0,
};

pub fn emitLiteral(char: u21, pos: usize) ErrorSet!Token {
    return Token{
        .id = .CHAR,
        .lexeme = try Rune.from(char),
        .pos = pos,
    };
}

pub fn emitReservedEscapesOnly(escaped: u21, char: u21, pos: usize) ErrorSet!?Token {
    if (isReserved(escaped)) {
        return Token{
            .id = .ESCAPED_CHAR,
            .lexeme = try Rune.from(char),
            .pos = pos,
        };
    }
    return null;
}

pub fn emitOperatorsOnly(char: u21, pos: usize) ErrorSet!?Token {
    return switch (char) {
        '.' => Token{
            .id = .DOT,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        ',' => Token{
            .id = .COMMA,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '^' => Token{
            .id = .CARET,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '$' => Token{
            .id = .DOLLAR,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '*' => Token{
            .id = .STAR,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '+' => Token{
            .id = .PLUS,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '?' => Token{
            .id = .QUESTION,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '|' => Token{
            .id = .PIPE,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '(' => Token{
            .id = .LPAREN,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        ')' => Token{
            .id = .RPAREN,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '[' => Token{
            .id = .LBRACKET,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        ']' => Token{
            .id = .RBRACKET,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '{' => Token{
            .id = .LBRACE,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '}' => Token{
            .id = .RBRACE,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        '-' => Token{
            .id = .DASH,
            .lexeme = try Rune.from(char),
            .pos = pos,
        },
        else => null,
    };
}

test "emitOperatorsOnly shoud tell apart parts of regex syntax and literals" {
    const cases = [_]struct {
        char: u21,
        expected: ?Token,
    }{
        .{
            .char = '.',
            .expected = Token{ .id = .DOT, .lexeme = try Rune.from('.') },
        },
        .{
            .char = ',',
            .expected = Token{ .id = .COMMA, .lexeme = try Rune.from(',') },
        },
        .{
            .char = '^',
            .expected = Token{ .id = .CARET, .lexeme = try Rune.from('^') },
        },
        .{
            .char = '$',
            .expected = Token{ .id = .DOLLAR, .lexeme = try Rune.from('$') },
        },
        .{
            .char = '*',
            .expected = Token{ .id = .STAR, .lexeme = try Rune.from('*') },
        },
        .{
            .char = '+',
            .expected = Token{ .id = .PLUS, .lexeme = try Rune.from('+') },
        },
        .{
            .char = '?',
            .expected = Token{ .id = .QUESTION, .lexeme = try Rune.from('?') },
        },
        .{
            .char = '|',
            .expected = Token{ .id = .PIPE, .lexeme = try Rune.from('|') },
        },
        .{
            .char = '(',
            .expected = Token{ .id = .LPAREN, .lexeme = try Rune.from('(') },
        },
        .{
            .char = ')',
            .expected = Token{ .id = .RPAREN, .lexeme = try Rune.from(')') },
        },
        .{
            .char = '[',
            .expected = Token{ .id = .LBRACKET, .lexeme = try Rune.from('[') },
        },
        .{
            .char = ']',
            .expected = Token{ .id = .RBRACKET, .lexeme = try Rune.from(']') },
        },
        .{
            .char = '{',
            .expected = Token{ .id = .LBRACE, .lexeme = try Rune.from('{') },
        },
        .{
            .char = '}',
            .expected = Token{ .id = .RBRACE, .lexeme = try Rune.from('}') },
        },
        .{
            .char = '-',
            .expected = Token{ .id = .DASH, .lexeme = try Rune.from('-') },
        },
        .{
            .char = 'a',
            .expected = null,
        },
    };

    for (cases) |c| {
        const result = try emitOperatorsOnly(c.char, 0);
        try testing.expectEqual(c.expected, result);
    }
}
