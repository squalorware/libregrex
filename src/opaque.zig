//! A wrapper for the C opaque types handling Zig payload types.

const std = @import("std");
const RegrexError = @import("./common/errors.zig").RegrexError;

/// Takes compile-time arguments of generic type
/// 
/// Returns a generic structure with the following fields:
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
