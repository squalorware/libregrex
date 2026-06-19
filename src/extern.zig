const std = @import("std");
const regrex = @import("root.zig");
const RegrexError = regrex.RegrexError;

pub const regrex_errcode_t = enum(c_uint) {
    REGREX_OK = 0,
    REGREX_ENOMATCH = 1,
    REGREX_ENOSPACE = 2,
    REGREX_EBADGRP = 3,
    REGREX_EBADUTF8 = 4,
    REGREX_ETOKEN = 5,
    REGREX_EEND = 6,
    REGREX_EEXPR = 7,
    REGREX_EBADESC = 8,
    REGREX_EBADREP = 9,
    REGREX_ERPAREN = 10,
    REGREX_ERBRACK = 11,
    REGREX_EINTERNAL = 255,
};

/// Converts Zig error set to C-compatible error code
fn toErrorCode(err: anyerror) regrex_errcode_t {
    return switch(err) {
        RegrexError.NoMatch => .REGREX_ENOMATCH,
        RegrexError.MemoryError => .REGREX_ENOSPACE,
        RegrexError.InvalidGroupIndex => .REGREX_EBADGRP,
        RegrexError.InvalidUnicode => .REGREX_EBADUTF8,
        RegrexError.UnexpectedToken => .REGREX_ETOKEN,
        RegrexError.UnexpectedEnd => .REGREX_EEND,
        RegrexError.ExpressionExpected => .REGREX_EEXPR,
        RegrexError.TrailingEscape => .REGREX_EBADESC,
        RegrexError.InvalidRepeat => .REGREX_EBADREP,
        RegrexError.UnmatchedParen => .REGREX_ERPAREN,
        RegrexError.UnmatchedBracket => .REGREX_ERBRACK,
        else => .REGREX_EINTERNAL,
    };
}

/// Maps C return status code to a string message
export fn regrex_error(code: regrex_errcode_t) [*:0]const u8 {
    return switch (code) {
        .REGREX_OK => "OK",
        .REGREX_ENOMATCH => "No matching group",
        .REGREX_ENOSPACE => "Memory allocation error",
        .REGREX_EBADGRP => "Group index is out of range",
        .REGREX_EBADUTF8 => "Invalid or malformed UTF-8 byte sequence",
        .REGREX_ETOKEN => "Unexpected or invalid Token in current context",
        .REGREX_EEND => "Unexpected end of pattern (EOF before construct is complete)",
        .REGREX_EEXPR => " Expected an expression; found an empty branch or sequence.",
        .REGREX_EBADESC => "Trailing backslash at the pattern end",
        .REGREX_EBADREP => "Invalid use of repetition operator",
        .REGREX_ERPAREN => "Closing right parenthesis missing",
        .REGREX_ERBRACK => "Closing right bracket missing",
        .REGREX_EINTERNAL => "Internal Error",
    };
}

const testing = std.testing;

test "extern.toErrorCode() maps Zig error set to corresponding return code" {
    try testing.expectEqual(
        .REGREX_EBADUTF8, 
        toErrorCode(RegrexError.InvalidUnicode),
    ); 
}

test "extern.regrex_error() maps return code to corresponding string message" {
    const msg = "Invalid or malformed UTF-8 byte sequence";
    try testing.expectEqualStrings(
        msg, 
        std.mem.span(regrex_error(.REGREX_EBADUTF8)),
    );
}
