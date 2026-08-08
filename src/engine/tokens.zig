const testing = @import("std").testing;
const Rune = @import("unicode").Rune;
const ManagedDynamicBuffer = @import("types").ManagedDynamicBuffer;
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
pub const Token = struct {
    typ: TokenType,
    /// Contains a Unicode code point from input at `pos`;
    ///
    /// `null` for EOF
    val: ?Rune,
    /// Zero-based code-point offset in the regex pattern.
    pos: usize = 0,
};

pub const TokenListBuffer = ManagedDynamicBuffer(Token, null);

/// Maps metacharacters to dedicated token types.
/// Returns `null` for regular literal characters.
pub fn mapRuneToTokenType(rune: Rune) ?TokenType {
    return switch (rune.raw()) {
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
        rune: Rune,
        expected: ?TokenType,
    }{
        .{ .rune = Rune.from('.'), .expected = .DOT },
        .{ .rune = Rune.from('^'), .expected = .CARET },
        .{ .rune = Rune.from('$'), .expected = .DOLLAR },
        .{ .rune = Rune.from('*'), .expected = .STAR },
        .{ .rune = Rune.from('+'), .expected = .PLUS },
        .{ .rune = Rune.from('?'), .expected = .QUESTION },
        .{ .rune = Rune.from('|'), .expected = .PIPE },
        .{ .rune = Rune.from('('), .expected = .LPAREN },
        .{ .rune = Rune.from(')'), .expected = .RPAREN },
        .{ .rune = Rune.from('['), .expected = .LBRACKET },
        .{ .rune = Rune.from(']'), .expected = .RBRACKET },
        .{ .rune = Rune.from('-'), .expected = .DASH },
        // Not a regex metacharacter
        .{ .rune = Rune.from('a'), .expected = null },
    };

    for (cases) |c| {
        const result = mapRuneToTokenType(c.rune);
        try testing.expectEqual(c.expected, result);
    }
}
