//! C-compatible data types and functions

/// A C-compatible representation for start and end indices
/// of a capture group inside the input string
///
/// `start` is inclusive. `end` is exclusive.
/// Both values are byte offsets, not UTF-8 scalar indices.
pub const ExtSpan = extern struct {
    start: usize,
    end: usize,
};

/// C-compatible enum specifying return codes used by the library
pub const ReturnCode = enum(c_int) {
    /// Shouldn't ever return; invalid syscall or not implemented
    ENOSYS = -1,
    /// Success
    OK = 0,
    /// Generic error (unknown)
    ERR = 1,
    /// Invalid argument
    REGREX_EARG = 2,
    /// No matching group
    REGREX_ENOMATCH = 3,
    /// Memory allocation error
    REGREX_ENOSPACE = 4,
    /// Index is out of range
    REGREX_ERANGE = 5,
    /// Exceeded maximum group count limit
    REGREX_EMAXGRP = 6,
    /// Invalid or malformed UTF-8
    REGREX_EBADUTF8 = 7,
    /// Unexpected Token
    REGREX_ETOKEN = 8,
    /// Unexpected end of pattern
    REGREX_EEND = 9,
    /// Expected expression
    REGREX_EEXPR = 10,
    /// Malformed or trailing backslash
    REGREX_EBADESC = 11,
    /// Invalid repetition operator
    REGREX_EBADREP = 12,
    /// Closing parenthesis missing
    REGREX_ERPAREN = 13,
    /// Closing bracket missing
    REGREX_ERBRACK = 14,
    /// Unexpected bytecode instruction
    REGREX_EINSTERR = 15,
};
