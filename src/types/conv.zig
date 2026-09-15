//! Various type casting/conversion utility functions
const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const ext = @import("./ext.zig");
const matching = @import("./matching.zig");
const meta = @import("./meta.zig");
const Flags = @import("./misc.zig").CompileFlags;
const testing = std.testing;

/// Converts a UTF-8 codepoint into a hexadecimal digit
pub fn toHexDigit(val: u21) ?u21 {
    return switch(val) {
        '0'...'9' => val - '0',
        'a'...'f' => val - 'a' + 10,
        'A'...'F' => val - 'A' + 10,
        else => null,
    };
}

/// Converts a UTF-8 codepoint into an octal digit
pub fn toOctDigit(val: u21) ?u21 {
    return switch(val) {
        '0'...'7' => val - '0',
        else => null,
    };
}

pub fn toErrorCode(err: anyerror) ext.C_ReturnCode {
    return switch(err) {
        ErrorSet.InvalidArgument => .REGREX_EARG,
        ErrorSet.NoMatch => .REGREX_ENOMATCH,
        ErrorSet.MemoryError => .REGREX_EMALLOC,
        ErrorSet.OutOfRange => .REGREX_ERANGE,
        ErrorSet.GroupBufferOverflow => .REGREX_EMAXGRP,
        ErrorSet.InvalidUnicode => .REGREX_EBADUTF8,
        ErrorSet.UnexpectedToken => .REGREX_ETOKEN,
        ErrorSet.UnexpectedEnd => .REGREX_EEND,
        ErrorSet.ExpressionExpected => .REGREX_EEXPR,
        ErrorSet.InvalidEscape  => .REGREX_EBADESC,
        ErrorSet.TrailingEscape => .REGREX_ETRAILESC,
        ErrorSet.InvalidRepeat => .REGREX_EBADREP,
        ErrorSet.UnmatchedParen => .REGREX_ERPAREN,
        ErrorSet.UnmatchedBracket => .REGREX_ERBRACK,
        ErrorSet.UnexpectedInstruction => .REGREX_EINSTERR,
        ErrorSet.InternalError => .ERR,
        else => .ENOSYS,
    };
}

pub fn toErrorSet(rc: ext.C_ReturnCode) ErrorSet {
    return switch (rc) {
        .OK => null,
        .REGREX_EARG => ErrorSet.InvalidArgument,
        .REGREX_ENOMATCH => ErrorSet.NoMatch,
        .REGREX_EMALLOC => ErrorSet.MemoryError,
        .REGREX_ERANGE => ErrorSet.OutOfRange,
        .REGREX_EMAXGRP => ErrorSet.GroupBufferOverflow,
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

pub fn toErrorMsg(rcode: ext.C_ReturnCode) ext.C_StaticString {
    return switch (rcode) {
        .OK => "OK",
        .ERR => "Internal error",
        .REGREX_EARG => "Invalid argument",
        .REGREX_ENOMATCH => "No matching group",
        .REGREX_EMALLOC => "Memory allocation error",
        .REGREX_ERANGE => "Index is out of range",
        .REGREX_EMAXGRP => "Exceeded maximum group count limit",
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

pub fn toC_Array(
    allocator: std.mem.Allocator, 
    comptime T: type, 
    sequence: []const T, 
    options: meta.T_FreeOptions(T),
) ErrorSet!?[*]T {
    if (sequence.len == 0) return null;
    defer allocator.free(sequence);
    
    if (!options.managed) {
        const result = allocator.dupe(T, sequence) catch return ErrorSet.MemoryError;
        return result.ptr;
    } else {
        var result = allocator.alloc(T, sequence.len) catch {
            for (sequence) |*item| {
                var owned = @constCast(item);
                if (options.destructor) |destroy| {
                    destroy(allocator, owned);
                } else if (comptime meta.hasDeinit(T)) {
                    owned.deinit(allocator);
                }
            }
            return ErrorSet.MemoryError;
        };
        var i: usize = 0;
        while(i < sequence.len) : (i += 1) {
            result[i] = allocator.create(T) catch {
                _ = ext.c_freeAllocated(T, allocator, result.ptr, result.len, .{
                    .destructor = options.destructor,
                    .managed = options.managed,
                });
                return ErrorSet.MemoryError;
            };
            result[i].* = sequence[i];  
        }
        return result.ptr;
    }
}

pub fn toC_String(alloc: std.mem.Allocator, input: ?[]const u8) ErrorSet!ext.C_String {
    const slice = input orelse return ErrorSet.InvalidArgument;

    const out = alloc.dupeSentinel(u8, slice, 0) catch {
        return ErrorSet.MemoryError;
    };
    return out.ptr;
}

pub fn toCompileFlags(mask: u8) Flags {
    return .{
        .ignore_case = mask & (1 << 0) != 0,
        .multiline = mask & (1 << 1) != 0,
        .dot_all = mask & (1 << 2) != 0,
    };
}
