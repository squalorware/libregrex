//! Shared error set for the regex frontend and compiler.

/// Common parsing and compilation errors
pub const Error = error {
    InvalidArgument,
    NoMatch,
    /// Index is out of range
    OutOfRange,
    /// Exceeded maximum group count limit
    GroupBufferOverflow,
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
