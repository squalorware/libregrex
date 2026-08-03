//! Convenience generic types that wrap over given complex types to simplify managing memory

const std = @import("std");
const Error = @import("./error.zig").Error;

/// Heap-allocated dynamic array of `T` that manages own memory
///
/// Takes an optional `callback` argument
/// in case `T` requires non-standard memory release logic.
pub fn ManagedArrayList(
    comptime T: type,
    comptime callback: ?fn(*type) void,
) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        inner: std.ArrayList(T),

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .allocator = alloc,
                .inner = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            if (callback) |cb| {
                cb();
            }
            for (self.inner.items) |*item| {
                item.deinit(self.allocator);
            }
            self.inner.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn append(self: *Self, item: T) Error!void {
            var owned = item;

            self.inner.append(self.allocator, item) catch {
                owned.deinit(self.allocator);
                return Error.MemoryError;
            };
        }

        pub fn len(self: Self) usize {
            return self.inner.items.len;
        }

        pub fn items(self: Self) []const T {
            return self.inner.items;
        }

        pub fn get(self: Self, i: usize) T {
            return self.inner.items[i];
        }

        pub fn set(self: *Self, i: usize, val: T) Error!void {
            if (i >= self.inner.items.len) {
                return Error.InvalidArgument;
            }

            self.inner.items[i].deinit(self.allocator);
            self.inner.items[i] = val;
        }

        pub fn clone(self: *Self) Error!Self {
            const copy = self.inner.clone() catch {
                return Error.MemoryError;
            };
            return .{
                .allocator = self.allocator,
                .inner = copy,
            };
        }

        pub fn pop(self: *Self) ?T {
            return self.inner.pop();
        }

        pub fn toOwnedSlice(self: *Self) Error![]T {
            return self.inner.toOwnedSlice(self.alloc) catch {
                return Error.MemoryError;
            };
        }
    };
}

pub fn ManagedOpaqueWrapper(
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
        pub fn init(
            alloc: std.mem.Allocator,
            val: Payload
        ) Error!*Opaque {
            const wrapped = alloc.create(Self) catch {
                return Error.MemoryError;
            };
            wrapped.* = .{ .value = val };
            return @ptrCast(wrapped);
        }

        /// Releases the memory used by the handler.
        ///
        /// Calls `free_cb` to deinitialize any resources used by `Payload`.
        /// After `value` is freed, destroys the wrapper.
        pub fn deinit(
            alloc: std.mem.Allocator,
            wrapped: ?*Opaque,
        ) void {
            const ptr = wrapped orelse return;
            const owned = unwrap(ptr);

            free_cb(alloc, &owned.value);

            owned.* = undefined;
            alloc.destroy(owned);
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
    };
}
