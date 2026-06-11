//! Shared error set for the regex frontend and compiler.

pub const Error = error {
    DanglingEscape,
    UnexpectedToken,
    UnexpectedEnd,
    ExpectedExpression,
    ExpectedClosingParen,
    ExpectedClosingBracket,
    UnsupportedRepeat,
};
