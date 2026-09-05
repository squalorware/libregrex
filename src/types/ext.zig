//! C-compatible data types and functions
const std = @import("std");
const meta = @import("./meta.zig");
const hasDeinit = meta.hasDeinit;
const Range = meta.Range;

/// C-compatible enum specifying return codes used by the library
pub const C_ReturnCode = enum(c_int) {
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

/// No-op destructor callback for buffer elements that require no cleanup
pub fn C_noOpDestructor(_: *anyopaque) callconv(.c) void {}

/// Generic C-compatible buffer storing fixed-size elements in raw memory
pub const C_GenericBuffer = extern struct {
    ptr: ?*anyopaque,
    capacity: usize,
    t_size: usize,
    t_align: usize,
    head: usize,
    tail: usize,
    len: usize,
    destroy_cb: *const fn(*anyopaque) callconv(.c) void,

    pub fn init(
        alloc: std.mem.Allocator,
        capacity: usize,
        destroy_cb: *const fn(*anyopaque) callconv(.c) void,
        item_align: usize,
        item_size: usize,
        out_buf: *C_GenericBuffer
    ) C_ReturnCode {
        var buffer: C_GenericBuffer = .{
            .ptr = null,
            .capacity = capacity,
            .t_size = item_size,
            .t_align = item_align,
            .head = 0,
            .tail = 0,
            .len = 0,
            .destroy_cb = destroy_cb,
        };

        if (capacity == 0) {
            out_buf.* = buffer;
            return .OK;
        }

        const byte_len = std.math.mul(usize, capacity, item_size) catch {
            return .REGREX_EMALLOC;
        };
        const ptr = alloc.rawAlloc(
            byte_len,
            std.mem.Alignment.fromByteUnits(item_align),
            @returnAddress(),
        ) orelse return .REGREX_EMALLOC;

        buffer.ptr = ptr;

        out_buf.* = buffer;
        return .OK;
    }

    /// Walks over each item in buffer and calls destructor callback on it
    pub fn deinit(alloc: std.mem.Allocator, buf: *C_GenericBuffer) void {
        if (buf.ptr) |ptr| {
            const bytes: [*]u8 = @ptrCast(ptr);

            var i: usize = 0;
            while (i < buf.len) : (i += 1) {
                const idx = (buf.tail + i) % buf.capacity;
                const offset = idx * buf.t_size;

                buf.destroy_cb(&bytes[offset]);
            }

            const byte_len = buf.capacity * buf.t_size;
            alloc.rawFree(
                bytes[0..byte_len],
                std.mem.Alignment.fromByteUnits(buf.t_align),
                @returnAddress(),
            );
        }
        buf.* = undefined;
    }

    pub fn push(buffer: *C_GenericBuffer, item: *const anyopaque) C_ReturnCode {
        if (buffer.len == buffer.capacity) return .REGREX_ERANGE;

        const ptr = buffer.ptr orelse return .REGREX_EARG;
        const src: [*]const u8 = @ptrCast(item);
        const dest: [*]u8 = @ptrCast(ptr);
        const offset = buffer.head * buffer.t_size;

        @memcpy(
            dest[offset..offset + buffer.t_size],
            src[0..buffer.t_size],
        );

        buffer.head = (buffer.head + 1) % buffer.capacity;
        buffer.len += 1;

        return .OK;
    }

    pub fn pop(buffer: *C_GenericBuffer, out: *anyopaque) C_ReturnCode {
        if (buffer.len == 0) return .REGREX_EARG;

        const ptr = buffer.ptr orelse return .REGREX_EARG;
        const src: [*]const u8 = @ptrCast(ptr);
        const dest: [*]u8 = @ptrCast(out);
        const offset = buffer.tail * buffer.t_size;

        @memcpy(
            dest[0..buffer.t_size],
            src[offset..offset + buffer.t_size],
        );

        buffer.tail = (buffer.tail + 1) % buffer.capacity;
        buffer.len -= 1;

        return .OK;
    }
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
