//! Defines the lexical tokens produced by lexer 
//! and consumed by the parser.
const Rune = @import("../common/types.zig").Rune;

/// Known types of tokens produced by lexer.
/// 
/// Some tokens can be assigned a context-specific meaning, e.g. `CARET`
/// can signify both a start anchor at the beginning of pattern, and
/// a character-class negation if comes right after `[`
pub const TokenType = enum {
    /// A literal unescaped Unicode code point
    CHAR,
    /// Escaped Unicode code point (treated as a literal after backslash)
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
    /// `?` 'Zero or one' quantifier
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
    EOF,
};

/// Single lexical token.
pub const Self = @This();

typ: TokenType,
/// Contains a Unicode code point from input at `pos`; 
/// 
/// `null` for EOF
val: ?Rune,
/// Zero-based code-point offset in the regex pattern.
pos: usize = 0,

/// Maps metacharacters to dedicated token types.
/// Returns `null` for regular literal characters.
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

const expectEqual = @import("std").testing.expectEqual;

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
        try expectEqual(c.expected, result);
    }
}
