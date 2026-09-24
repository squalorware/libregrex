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
    /// `-` Character-class range separator
    DASH,
    /// Pattern end sentinel
    EOP,
};

/// Instance of Token
///
/// Holds corresponding character from input and its position within it
const Lexeme = struct {
    val: ?Rune,
    pos: usize = 0,
};

pub const Token = union(TokenId) {
    /// A literal unescaped Unicode code point
    CHAR: Lexeme,
    /// Escaped Unicode code point (treated as a literal after backslash)
    /// or Unicode character class or assertion
    ESCAPED_CHAR: Lexeme,
    /// `.` Wildcard
    DOT: Lexeme,
    /// `^` Start anchor or character class negation
    CARET: Lexeme,
    /// `$` End anchor
    DOLLAR: Lexeme,
    /// `*` 'Zero or more' quantifier
    STAR: Lexeme,
    /// `+` 'One or more' quantifier
    PLUS: Lexeme,
    /// `?` 'Zero or one' quantifier or non-capture group marker or inline flag marker
    QUESTION: Lexeme,
    /// `|` Branching operator
    PIPE: Lexeme,
    /// `(` Opening group delimiter
    LPAREN: Lexeme,
    /// `)` Closing group delimiter
    RPAREN: Lexeme,
    /// `[` Opening character-class (e.g. `[a-z]`) delimiter
    LBRACKET: Lexeme,
    /// `]` Closing character-class delimiter
    RBRACKET: Lexeme,
    /// `-` Character-class range separator
    DASH: Lexeme,
    /// Pattern end sentinel
    EOP: Lexeme,

    pub fn val(self: Token) ?Rune {
        return switch (self) {
            inline else => |data| data.val,
        };
    }

    pub fn pos(self: Token) usize {
        return switch (self) {
            inline else => |data| data.usize,
        };
    }

    pub fn id(self: Token) TokenId {
        return std.meta.activeTag(self);
    }
};

pub fn emitLiteral(char: u21, pos: usize) ErrorSet!Token {
    return Token{
        .CHAR = Lexeme{
            .val = try Rune.from(char),
            .pos = pos,
        },
    };
}

pub fn emitReservedEscapesOnly(escaped: u21, char: u21, pos: usize) ErrorSet!?Token {
    if (isReserved(escaped)) {
        return .{ .ESCAPED_CHAR = .{
            .val = try Rune.from(char),
            .pos = pos,
        } };
    }
    return null;
}

pub fn emitOperatorsOnly(char: u21, pos: usize) ErrorSet!?Token {
    return switch (char) {
        '.' => .{ .DOT = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '^' => .{ .CARET = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '$' => .{ .DOLLAR = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '*' => .{ .STAR = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '+' => .{ .PLUS = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '?' => .{ .QUESTION = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '|' => .{ .PIPE = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '(' => .{ .LPAREN = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        ')' => .{ .RPAREN = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '[' => .{ .LBRACKET = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        ']' => .{ .RBRACKET = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        '-' => .{ .DASH = .{
            .val = try Rune.from(char),
            .pos = pos,
        } },
        else => null,
    };
}

test "emitOperatorsOnly shoud tell apart parts of regex syntax and literals" {
    const cases = [_]struct {
        char: u21,
        expected: ?Token,
    }{
        .{ .char = '.', .expected = .{ .DOT = .{ .val = try Rune.from('.') } } },
        .{ .char = '^', .expected = .{ .CARET = .{ .val = try Rune.from('^') } } },
        .{ .char = '$', .expected = .{ .DOLLAR = .{ .val = try Rune.from('$') } } },
        .{ .char = '*', .expected = .{ .STAR = .{ .val = try Rune.from('*') } } },
        .{ .char = '+', .expected = .{ .PLUS = .{ .val = try Rune.from('+') } } },
        .{ .char = '?', .expected = .{ .QUESTION = .{ .val = try Rune.from('?') } } },
        .{ .char = '|', .expected = .{ .PIPE = .{ .val = try Rune.from('|') } } },
        .{ .char = '(', .expected = .{ .LPAREN = .{ .val = try Rune.from('(') } } },
        .{ .char = ')', .expected = .{ .RPAREN = .{ .val = try Rune.from(')') } } },
        .{ .char = '[', .expected = .{ .LBRACKET = .{ .val = try Rune.from('[') } } },
        .{ .char = ']', .expected = .{ .RBRACKET = .{ .val = try Rune.from(']') } } },
        .{ .char = '-', .expected = .{ .DASH = .{ .val = try Rune.from('-') } } },
        .{ .char = 'a', .expected = null },
    };

    for (cases) |c| {
        const result = try emitOperatorsOnly(c.char, 0);
        try testing.expectEqual(c.expected, result);
    }
}
