//! Shared error set for the regex frontend and compiler.
const conv = @import("./conv.zig");

pub const ErrorSet = error{
    /// Invalid argument
    InvalidArgument,
    /// No matching group
    NoMatch,
    /// Index is out of range
    OutOfRange,
    /// Exceeded maximum group count limit
    ExceedsCapacity,
    /// Expected an expression; found an empty branch/sequence.
    ExpressionExpected,
    /// Invalid use of repetition operator `*`
    InvalidRepeat,
    /// Memory allocation error
    MemoryError,
    /// Invalid or malformed UTF-8 codepoint
    InvalidUnicode,
    /// Malformed escape sequence
    InvalidEscape,
    /// Trailing backslash at the pattern end
    TrailingEscape,
    /// Token invalid in current context
    UnexpectedToken,
    /// Instruction invalid in current context
    UnexpectedInstruction,
    /// Unexpected end of pattern (EOF before construct complete)
    UnexpectedEnd,
    /// Missing `)`
    UnmatchedParen,
    /// Missing `]`
    UnmatchedBracket,
    /// Non-specific generic error
    InternalError,
};
