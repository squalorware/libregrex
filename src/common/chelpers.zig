//! Helpers for the C ABI
//! 
//! The module contains utilities for type conversions between C and Zig

const std = @import("std");
const RegrexError = @import("./errors.zig").RegrexError;

/// Converts a C string to Zig slice.
/// 
/// Receives a pointer to a starting index of a byte buffer
/// and the number of bytes `len` to expose
/// 
/// Returns an empty slice if `len` is 0 even if `ptr` is null
/// 
/// Returns `null` if `len > 0` and `ptr` is null
/// 
/// Returns a slice that starts with 0 and ends at received string length
pub fn toOwnedSlice(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    if (len == 0) return "";

    const non_null = ptr orelse return null;
    return non_null[0..len];
}

pub fn toCString(
    alloc: std.mem.Allocator,
    buffer: ?[]const u8,
) RegrexError![*:0]const u8 {
    const buf = buffer orelse return RegrexError.InvalidArgument;

    const sent_buf = alloc.dupeZ(u8, buf) catch {
        return RegrexError.MemoryError;
    };

    return sent_buf.ptr;
}

pub fn storeBuffer(
    alloc: std.mem.Allocator,
    buf: []u8, 
    out_obj: *?[*]u8, 
    out_len: *usize
) void {
    if (buf.len == 0) {
        alloc.free(buf);
        out_obj.* = null;
        out_len.* = 0;
        return;
    }

    out_obj.* = buf.ptr;
    out_len.* = buf.len;
}


pub fn WrappedOpaque(
    comptime Opaque: type,
    comptime Payload: type,
    comptime free_cb: fn(std.mem.Allocator, *Payload) void,
) type {
    return struct {
        const Self = @This();
        value: Payload,

        pub fn create(
            alloc: std.mem.Allocator, 
            val: Payload
        ) RegrexError!*Opaque {
            const wrapped = alloc.create(Self) catch {
                return RegrexError.MemoryError;
            };
            wrapped.* = .{ .value = val };
            return @ptrCast(wrapped);
        }

        pub fn unwrap(ptr: *Opaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        pub fn unwrapConst(ptr: *const Opaque) *const Self {
            return @ptrCast(@alignCast(ptr));
        }

        pub fn destroy(
            alloc: std.mem.Allocator,
            wrapped: ?*Opaque,
        ) void {
            const ptr = wrapped orelse return;
            const owned = unwrap(ptr);

            free_cb(alloc, &owned.value);

            owned.* = undefined;
            alloc.destroy(owned);
        }
    };
}
