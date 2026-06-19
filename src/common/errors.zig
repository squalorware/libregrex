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

/// C ABI status codes
pub const RegrexStatus = enum(c_uint) {
    ok = 0,
    enomatch = 1,
    /// Invalid group index
    egrp = 3,
    /// Invalid argument
    earg = 4,
    /// Out of Memory
    espace = 5,
    /// Invalid Unicode
    eutf = 6,
    /// Unexpected Token
    etok = 7,
    /// Expression expected
    eexpr = 8,
    /// Invalid Repetition
    erep = 9,
    /// Trailing escape character
    eesc = 10,
    /// Unexpected EOF
    eend = 11,
    /// Closing parenthesis missing
    erparen = 12,
    /// Closing bracket missing
    erbrack = 13,
    /// Generic error
    unknown = 255,
};
