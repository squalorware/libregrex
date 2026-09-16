//! C-compatible data types and functions
const std = @import("std");
const conv = @import("./conv.zig");
const ErrorSet = @import("./error.zig").ErrorSet;
const matching = @import("./matching.zig");
const meta = @import("./meta.zig");
const Match = matching.Match;
const Span = matching.Span;

/// Explicitly use signed 8-bit integer to ensure memory layout compatibility with C ABI
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

/// NULL-terminated `const char*`, immutable, borrowed
pub const C_StaticString = [*:0]const u8;

/// NULL-terminated `char*`, mutable, owned by allocator 
pub const C_String = [*:0]u8;

pub const C_Match = extern struct {
    ptr: ?*anyopaque,
    cgroups: [*]Span,
    groups_len: usize,

    const destroyCallback: meta.T_DestructorCallback(Match) = matching.freeMatchCallback;

    pub fn create(alloc: std.mem.Allocator, match: ?Match) ErrorSet!C_Match {
        const m = match orelse return ErrorSet.InvalidArgument;

        const ptr = alloc.create(Match) catch return ErrorSet.MemoryError;
        ptr.* = m;

        return .{
            .ptr = @ptrCast(ptr),
            .cgroups = m.groups.ptr,
            .groups_len = m.groups.len,
        };
    }

    pub fn destroy(ptr: *C_Match, alloc: std.mem.Allocator) void {
        const self = ptr.unwrap() catch return;
        const cb = destroyCallback orelse return;
        cb(alloc, self);
        self.* = undefined;
        alloc.destroy(self);
    }

    pub fn unwrap(self: *C_Match) ErrorSet!*Match {
        const m = self.ptr orelse return ErrorSet.InvalidArgument;
        return @ptrCast(@alignCast(m));
    }

    pub fn unwrapConst(self: *C_Match) ErrorSet!*const Match {
        const m = self.ptr orelse return ErrorSet.InvalidArgument;
        return @ptrCast(@alignCast(m));
    }
};

/// Generic destructor for allocated data types like arrays
pub fn c_freeBuffer(
    comptime T: type,
    alloc: std.mem.Allocator,
    ptr: ?[*]T,
    len: usize,
    destroy_cb: meta.T_DestructorCallback(T),
) void {
    const buf = ptr orelse return;

    _ = meta.freeAny(T, alloc, buf[0..len], destroy_cb);
}

