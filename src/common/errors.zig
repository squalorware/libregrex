//! Shared error set for the regex frontend and compiler.

/// Common parsing and compilation errors
pub const RegrexError = error {
    NoMatch,
    /// Group index is outside of range
    InvalidGroupIndex,
    /// Expected an expression; found an empty branch/sequence.
    ExpressionExpected,
    /// Invalid use of repetition operator `*`
    InvalidRepeat,
    /// Out of memory
    MemoryError,
    /// An invalid or broken UTF-8 character
    InvalidUnicode,
    /// Trailing backslash at the pattern end
    TrailingEscape,
    /// Token invalid in current context
    UnexpectedToken,
    /// Unexpected end of pattern (EOF before construct complete)
    UnexpectedEnd,
    /// Missing `)`
    UnmatchedParen,
    /// Missing `]`
    UnmatchedBracket,
};
