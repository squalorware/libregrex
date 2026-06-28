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

/// Converts a Zig slice to a C string.
/// 
/// Caller owns returned pointer and must release it with the same allocator 
/// and correct allocation length. The allocation length is `buffer.len + 1`
/// because `dupeSentinel` adds a trailing zero byte.
/// 
/// Returns a pointer to a newly allocated null-terminated byte buffer
/// 
/// Returns `RegrexError.InvalidArgument` if `buffer` is null
/// 
/// Returns `RegrexError.MemoryError` if allocation failed
pub fn toCString(
    alloc: std.mem.Allocator,
    buffer: ?[]const u8,
) RegrexError![*:0]const u8 {
    const buf = buffer orelse return RegrexError.InvalidArgument;

    const sent_buf = alloc.dupeSentinel(u8, buf, 0) catch {
        return RegrexError.MemoryError;
    };

    return sent_buf.ptr;
}

/// Stores a pointer to the start of an allocated byte buffer
/// and its length to the output parameters.
/// 
/// On success ransfers ownership to the caller. 
/// The caller must release the buffer manually.
/// 
/// On failure releases buffer and sets output parameters 
/// to null and 0 respectively
pub fn storeBuffer(
    alloc: std.mem.Allocator,
    buf: []u8, 
    out_ptr: *?[*]u8, 
    out_len: *usize
) void {
    if (buf.len == 0) {
        alloc.free(buf);
        out_ptr.* = null;
        out_len.* = 0;
        return;
    }

    out_ptr.* = buf.ptr;
    out_len.* = buf.len;
}

/// Returns a wrapper for the C opaque type handling Zig payload type.
/// 
/// - `Opaque` - a public C opaque type
/// - `Payload` - the internal Zig type handled by `Opaque`
/// - `free_cb` - callback destructor to release `Payload`. 
/// Must not release wrapper, only resources owned by `Payload` 
pub fn WrappedOpaque(
    comptime Opaque: type,
    comptime Payload: type,
    comptime free_cb: fn(std.mem.Allocator, *Payload) void,
) type {
    return struct {
        const Self = @This();
        value: Payload,

        /// Allocates memory for the new opaque wrapper handler and moves `val` into it.
        /// 
        /// Returns newly created handler on success.
        /// Transfers ownership of `val` to handler. Must be released with `destroy()`
        /// 
        /// Returns `RegrexError.MemoryError` if failed. 
        /// Ownership of `val` remains with the caller
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

        /// Converts opaque handler into internal mutable wrapper type.
        /// 
        /// The pointer must be created with `create()` for this exact wrapper type.
        /// Passing wrong pointer results in undefined behaviour.
        pub fn unwrap(ptr: *Opaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        /// Converts opaque handler into internal immutable wrapper type.
        /// 
        /// The pointer must be created with `create()` for this exact wrapper type.
        /// Passing wrong pointer results in undefined behaviour.
        pub fn unwrapConst(ptr: *const Opaque) *const Self {
            return @ptrCast(@alignCast(ptr));
        }

        /// Releases the memory used by the handler.
        /// 
        /// Calls `free_cb` to deinitialize any resources used by `Payload`.
        /// After `value` is freed, destroys the wrapper.
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

const testing = std.testing;

test "toOwnedSlice() should return a borrowed slice for non-null pointer" {
    const input = "lolkek";

    const result = toOwnedSlice(input.ptr, input.len) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("lolkek", result);
}

test "toOwnedSlice() should return empty slice for zero length" {
    const result = toOwnedSlice(@as(?[*]const u8, null), 0) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("", result);
}

test "toOwnedSlice() should return null for missing non-empty pointer" {
    const result = toOwnedSlice(@as(?[*]const u8, null), 4);

    try testing.expect(result == null);
}

test "toCString() should return a copied buffer with a trailing zero byte" {
    const allocator = testing.allocator;
    const input = "lolkek";

    const c_str = try toCString(allocator, input);
    defer {
        const owned: [*:0]u8 = @constCast(c_str);
        allocator.free(owned[0 .. std.mem.len(c_str) + 1]);
    }

    try testing.expectEqualStrings("lolkek", std.mem.span(c_str));
    try testing.expectEqual(@as(u8, 0), c_str[input.len]);
}

test "toCString() should return RegrexError.InvalidArgument error for null buffer" {
    const allocator = testing.allocator;

    try testing.expectError(
        RegrexError.InvalidArgument,
        toCString(allocator, @as(?[]const u8, null)),
    );
}

test "storeBuffer() should store non-empty buffer and transfer ownership" {
    const allocator = testing.allocator;
    const buf = try allocator.dupe(u8, "kek");

    var out_ptr: ?[*]u8 = null;
    var out_len: usize = 0;

    storeBuffer(allocator, buf, &out_ptr, &out_len);

    try testing.expect(out_ptr != null);
    try testing.expectEqual(@as(usize, 3), out_len);
    try testing.expectEqualStrings("kek", out_ptr.?[0 .. out_len]);

    allocator.free(out_ptr.?[0 .. out_len]);
}

test "storeBuffer() should free empty buffer and store null output" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 0);

    var out_ptr: ?[*]u8 = undefined;
    var out_len: usize = 420;

    storeBuffer(allocator, buf, &out_ptr, &out_len);

    try testing.expect(out_ptr == null);
    try testing.expectEqual(@as(usize, 0), out_len);
}

const TestOpaque = opaque {};
const TestPayload = struct {
    value: usize,
    freed: *bool,
};

fn freeTestPayload(
    alloc: std.mem.Allocator, 
    payload: *TestPayload
) void {
    _ = alloc;
    payload.freed.* = true;
}

test "WrappedOpaque() should create, unwrap and destroy an opaque handler" {
    const allocator = testing.allocator;
    const WrappedTest = WrappedOpaque(TestOpaque, TestPayload, freeTestPayload);

    var freed = false;

    const wrapped = try WrappedTest.create(allocator, .{
        .value = 42,
        .freed = &freed,
    });

    const owned_mut = WrappedTest.unwrap(wrapped);
    try testing.expectEqual(@as(usize, 42), owned_mut.value.value);

    const owned_const  = WrappedTest.unwrapConst(wrapped);
    try testing.expectEqual(@as(usize, 42), owned_const.value.value);

    WrappedTest.destroy(allocator, wrapped);

    try testing.expect(freed);
}

test "WrappedOpaque().destroy should not fail when passed null value" {
    const allocator = testing.allocator;
    const WrappedTest = WrappedOpaque(TestOpaque, TestPayload, freeTestPayload);

    WrappedTest.destroy(allocator, @as(?*TestOpaque, null));
}
