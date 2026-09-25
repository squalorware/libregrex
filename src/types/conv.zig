//! Various type casting/conversion utility functions
const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const matching = @import("./matching.zig");
const meta = @import("./meta.zig");
const testing = std.testing;

/// Converts a UTF-8 codepoint into a hexadecimal digit
pub fn toHexDigit(val: u21) ?u21 {
    return switch (val) {
        '0'...'9' => val - '0',
        'a'...'f' => val - 'a' + 10,
        'A'...'F' => val - 'A' + 10,
        else => null,
    };
}

/// Converts a UTF-8 codepoint into an octal digit
pub fn toOctDigit(val: u21) ?u21 {
    return switch (val) {
        '0'...'7' => val - '0',
        else => null,
    };
}

/// Explicitly use signed 8-bit integer to ensure memory layout compatibility with C ABI
pub const ReturnCode = enum(i8) {
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
    REGREX_EMAXCAP = 6,
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

pub fn toErrorCode(err: anyerror) ReturnCode {
    return switch (err) {
        ErrorSet.InvalidArgument => .REGREX_EARG,
        ErrorSet.NoMatch => .REGREX_ENOMATCH,
        ErrorSet.MemoryError => .REGREX_EMALLOC,
        ErrorSet.OutOfRange => .REGREX_ERANGE,
        ErrorSet.ExceedsCapacity => .REGREX_EMAXCAP,
        ErrorSet.InvalidUnicode => .REGREX_EBADUTF8,
        ErrorSet.UnexpectedToken => .REGREX_ETOKEN,
        ErrorSet.UnexpectedEnd => .REGREX_EEND,
        ErrorSet.ExpressionExpected => .REGREX_EEXPR,
        ErrorSet.InvalidEscape => .REGREX_EBADESC,
        ErrorSet.TrailingEscape => .REGREX_ETRAILESC,
        ErrorSet.InvalidRepeat => .REGREX_EBADREP,
        ErrorSet.UnmatchedParen => .REGREX_ERPAREN,
        ErrorSet.UnmatchedBracket => .REGREX_ERBRACK,
        ErrorSet.UnexpectedInstruction => .REGREX_EINSTERR,
        ErrorSet.InternalError => .ERR,
        else => .ENOSYS,
    };
}

pub fn toErrorSet(rc: ReturnCode) ErrorSet {
    return switch (rc) {
        .OK => null,
        .REGREX_EARG => ErrorSet.InvalidArgument,
        .REGREX_ENOMATCH => ErrorSet.NoMatch,
        .REGREX_EMALLOC => ErrorSet.MemoryError,
        .REGREX_ERANGE => ErrorSet.OutOfRange,
        .REGREX_EMAXCAP => ErrorSet.ExceedsCapacity,
        .REGREX_EBADUTF8 => ErrorSet.InvalidUnicode,
        .REGREX_ETOKEN => ErrorSet.UnexpectedToken,
        .REGREX_EEND => ErrorSet.UnexpectedEnd,
        .REGREX_EEXPR => ErrorSet.ExpressionExpected,
        .REGREX_EBADESC => ErrorSet.InvalidEscape,
        .REGREX_ETRAILESC => ErrorSet.TrailingEscape,
        .REGREX_EBADREP => ErrorSet.InvalidRepeat,
        .REGREX_ERPAREN => ErrorSet.UnmatchedParen,
        .REGREX_ERBRACK => ErrorSet.UnmatchedBracket,
        .REGREX_EINSTERR => ErrorSet.UnexpectedInstruction,
        .ERR => ErrorSet.InternalError,
    };
}

pub fn toErrorMsg(rcode: ReturnCode) [*:0]const u8 {
    return switch (rcode) {
        .OK => "OK",
        .ERR => "Internal error",
        .REGREX_EARG => "Invalid argument",
        .REGREX_ENOMATCH => "No matching group",
        .REGREX_EMALLOC => "Memory allocation error",
        .REGREX_ERANGE => "Index is out of range",
        .REGREX_EMAXCAP => "Exceeded maximum group count limit",
        .REGREX_EBADUTF8 => "Parsing error: Invalid or malformed UTF-8 code point",
        .REGREX_ETOKEN => "Parsing error: Unexpected token",
        .REGREX_EEND => "Parsing error: Unexpected end of pattern",
        .REGREX_EEXPR => "Parsing error: Expected an expression",
        .REGREX_EBADESC => "Syntax error: Malformed escape sequence",
        .REGREX_ETRAILESC => "Syntax error: Trailing backslash",
        .REGREX_EBADREP => "Syntax error: Invalid repetition operator",
        .REGREX_ERPAREN => "Syntax error: Closing parenthesis missing",
        .REGREX_ERBRACK => "Syntax error: Closing bracket missing",
        .REGREX_EINSTERR => "Compilation error: Unexpected bytecode instruction",
        else => "Unknown error",
    };
}

/// Casts string to equivalent of `char*` in C
///
/// Returns a raw pointer to a null-terminated buffer owned by the caller
pub fn toC_String(alloc: std.mem.Allocator, input: ?[]const u8) ErrorSet![*:0]u8 {
    const slice = input orelse return ErrorSet.InvalidArgument;

    const out = alloc.dupeSentinel(u8, slice, 0) catch {
        return ErrorSet.MemoryError;
    };
    return out.ptr;
}
