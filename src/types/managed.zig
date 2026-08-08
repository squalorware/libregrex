//! Convenience generic types that wrap over given complex types to simplify managing memory

const std = @import("std");
const Error = @import("./error.zig").Error;
const testing = std.testing;

/// Heap-allocated dynamic array that owns its stored `T` values.
///
/// By default, stored values are released using:
///
///     item.deinit(allocator)
///
/// `deinit_cb` may be provided when `T` requires different destruction
/// logic. In that case, the callback is used instead of `T.deinit()`.
///
/// Operations that accept a `T` by value (`init`, `append`, and `set`) transfer
/// ownership of that value to the list on success.
///
/// Operations that remove values (`pop` and `toOwnedSlice`) transfer ownership
/// from the list to the caller.
pub fn ManagedArrayList(
    comptime T: type,
    comptime deinit_cb: ?*const fn(
        item: *T,
        allocator: std.mem.Allocator,
    ) void,
) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        inner: std.ArrayList(T),

        /// Creates a managed list.
        ///
        /// If `buffer` is provided, its values are copied into the list and
        /// ownership of those values transfers to the list on success.
        ///
        /// The caller retains ownership of the `buffer` storage itself, but
        /// must not separately deinitialize its `T` values after successful
        /// initialization.
        pub fn init(alloc: std.mem.Allocator, buffer: ?[]const T) Error!Self {
            var inner: std.ArrayList(T) = .empty;

            if (buffer) |buf| {
                inner.appendSlice(alloc, buf) catch {
                    return Error.MemoryError;
                };
            }

            return .{
                .allocator = alloc,
                .inner = inner,
            };
        }

        /// Releases an individual owned value according to this list's
        /// destruction policy.
        fn deinitItem(self: Self, item: *T) void {
            if (deinit_cb) |callback| {
                callback(item, self.allocator);
            } else {
                item.deinit(self.allocator);
            }
        }

        /// Releases all owned values and the backing array.
        ///
        /// `self` becomes invalid after this call.
        pub fn deinit(self: *Self) void {
            for (self.inner.items) |*item| {
                self.deinitItem(item);
            }
            self.inner.deinit(self.allocator);
            self.* = undefined;
        }

        /// Appends `item` and transfers its ownership to the list.
        ///
        /// If allocation fails, `item` is deinitialized before
        /// `Error.MemoryError` is returned.
        pub fn append(self: *Self, item: T) Error!void {
            var owned = item;

            self.inner.append(self.allocator, owned) catch {
                self.deinitItem(&owned);
                return Error.MemoryError;
            };
        }

        pub fn len(self: *const Self) usize {
            return self.inner.items.len;
        }

        pub fn items(self: *const Self) []const T {
            return self.inner.items;
        }

        /// Returns a borrowed pointer to the value at `i`.
        ///
        /// Returns `Error.InvalidArgument` if `i` is outside the list.
        pub fn get(self: *const Self, i: usize) Error!*const T {
            if (i > self.inner.items.len) {
                return Error.OutOfRange;
            }

            return &self.inner.items[i];
        }

        /// Replaces the value at `i`.
        ///
        /// The previous value is deinitialized. Ownership of `val` transfers
        /// to the list on success.
        ///
        /// If `i` is invalid, ownership of `val` remains with the caller.
        pub fn set(self: *Self, i: usize, val: T) Error!void {
            if (i >= self.inner.items.len) {
                return Error.OutOfRange;
            }

            self.deinitItem(&self.inner.items[i]);
            self.inner.items[i] = val;
        }

        pub fn clone(self: *Self) Error!Self {
            const copy = self.inner.clone(self.alloc) catch {
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

        /// Transfers ownership of the backing allocation and all stored values
        /// to the caller.
        ///
        /// On success, this list remains valid but becomes empty.
        ///
        /// The caller is responsible for deinitializing every returned `T`
        /// according to the same destruction policy and freeing the slice with
        /// this list's allocator.
        pub fn toOwnedSlice(self: *Self) Error![]T {
            return self.inner.toOwnedSlice(self.allocator) catch {
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
