//! C-compatible data types and functions
const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const meta = @import("./meta.zig");

/// C-compatible enum specifying return codes used by the library
pub const C_ReturnCode = enum(i8) {
    /// Shouldn't ever return; invalid syscall or not implemented
    ENOSYS = -1,
    /// Success
    OK = 0,
    /// Non-specific generic error
    ERR = 1,
    /// Invalid argument
    REGREX_EARG = 2,
    /// No matching group
    REGREX_ENOMATCH = 3,
    /// Memory allocation error
    REGREX_EMALLOC = 4,
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
    /// Malformed escape sequence
    REGREX_EBADESC = 11,
    /// Trailing backslash
    REGREX_ETRAILESC = 12,
    /// Invalid repetition operator
    REGREX_EBADREP = 13,
    /// Closing parenthesis missing
    REGREX_ERPAREN = 14,
    /// Closing bracket missing
    REGREX_ERBRACK = 15,
    /// Unexpected bytecode instruction
    REGREX_EINSTERR = 16,
};

/// Opaque handler for result type produced by matching operations.
///
/// It is allocated on the heap and must be released.
pub const C_MatchHolder = opaque {};

/// Opaque handler for a lazy iterator created by the compiled pattern.
///
/// The parent pattern and input buffer must outlive the iterator.
///
/// It is allocated on the heap and must be released
pub const C_IterHolder = opaque {};
