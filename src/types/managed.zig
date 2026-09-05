//! Convenience generic types that wrap over given complex types to simplify managing memory

const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const hasDeinit = @import("./meta.zig").hasDeinit;
const testing = std.testing;

/// Heap-allocated dynamic array that owns its stored `T` values.
///
/// By default, stored values are released using:
///
///     item.deinit(allocator)
///
/// `T_destructor_cb` may be provided when `T` requires different release logic.
///  In such case, the passed callback function is used instead of `T.deinit()`.
///
/// Operations that accept a `T` by value (`init`, `append`, and `set`) transfer
/// ownership of that value to the list on success.
///
/// Operations that remove values (`pop` and `toOwnedSlice`) transfer ownership
/// from the list to the caller.
pub fn ManagedDynamicBuffer(
    comptime T: type,
    comptime T_destructor_cb: ?*const fn(
        allocator: std.mem.Allocator,
        item: *T,
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
        pub fn init(alloc: std.mem.Allocator, buffer: ?[]const T) ErrorSet!Self {
            var inner: std.ArrayList(T) = .empty;

            if (buffer) |buf| {
                inner.appendSlice(alloc, buf) catch {
                    return ErrorSet.MemoryError;
                };
            }

            return .{
                .allocator = alloc,
                .inner = inner,
            };
        }

        /// Releases an individual owned value according to this list's
        /// destruction policy.
        pub fn deinitItem(self: Self, item: *T) void {
            if (T_destructor_cb) |callback_fn| {
                callback_fn(self.allocator, item);
            } else if (comptime hasDeinit(T)) {
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
        pub fn append(self: *Self, item: T) ErrorSet!void {
            var owned = item;

            self.inner.append(self.allocator, owned) catch {
                self.deinitItem(&owned);
                return ErrorSet.MemoryError;
            };
        }

        /// Extends the buffer with `slice`.
        ///
        /// The input slice remains owned by the caller.
        ///
        /// On success, ownership of the copied `T` values transfers to the list;
        /// the caller must not separately deinitialize the original values.
        ///
        /// On failure, ownership remains entirely with the caller.
        pub fn appendSlice(self: *Self, slice: []const T) ErrorSet!void {
            self.inner.appendSlice(self.allocator, slice) catch {
                return ErrorSet.MemoryError;
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
        pub fn get(self: *const Self, i: usize) ErrorSet!*const T {
            if (i >= self.inner.items.len) {
                return ErrorSet.OutOfRange;
            }

            return &self.inner.items[i];
        }

        /// Replaces the value at `i`.
        ///
        /// The previous value is deinitialized. Ownership of `val` transfers
        /// to the list on success.
        ///
        /// If `i` is invalid, ownership of `val` remains with the caller.
        pub fn set(self: *Self, i: usize, val: T) ErrorSet!void {
            if (i >= self.inner.items.len) {
                return ErrorSet.OutOfRange;
            }

            self.deinitItem(&self.inner.items[i]);
            self.inner.items[i] = val;
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
        pub fn toOwnedSlice(self: *Self) ErrorSet![]T {
            return self.inner.toOwnedSlice(self.allocator) catch {
                return ErrorSet.MemoryError;
            };
        }
    };
}

const TestItem = struct {
    id: usize,
    data: []u8,
    deinit_count: *usize,

    pub fn init(alloc: std.mem.Allocator, id: usize, deinit_count: *usize) !TestItem {
        return .{ 
            .id = id, 
            .data = try alloc.dupe(u8, "test"),
            .deinit_count = deinit_count 
        };
    }

    pub fn deinit(self: *TestItem, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.deinit_count.* += 1;
        self.* = undefined;
    }
};

const TestItemList = ManagedDynamicBuffer(TestItem, null);

fn expectTestItemIds(list: *const TestItemList, expected: []const usize) !void {
    try testing.expectEqual(expected.len, list.len());

    for (expected, 0..) |expected_id, i| {
        try testing.expectEqual(
            expected_id,
            (try list.get(i)).id,
        );
    }
}

test "ManagedDynamicBuffer init empty and append" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try testing.expectEqual(@as(usize, 0), list.len());

        const item = try TestItem.init(
            allocator,
            67,
            &deinit_count,
        );

        try list.append(item);

        try expectTestItemIds(&list, &.{67});
    }

    try testing.expectEqual(@as(usize, 1), deinit_count);
}

test "ManagedDynamicBuffer init with slice and append" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        var initial = [_]TestItem{
            try TestItem.init(allocator, 13, &deinit_count),
            try TestItem.init(allocator, 42, &deinit_count),
            try TestItem.init(allocator, 67, &deinit_count),
        };

        var list = try TestItemList.init(allocator, initial[0..]);
        defer list.deinit();

        try expectTestItemIds(&list, &.{ 13, 42, 67 });

        const item = try TestItem.init(
            allocator,
            420,
            &deinit_count,
        );

        try list.append(item);

        try expectTestItemIds(&list, &.{ 13, 42, 67, 420 });
    }

    try testing.expectEqual(@as(usize, 4), deinit_count);
}

test "ManagedDynamicBuffer init empty and appendSlice" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        var appended = [_]TestItem{
            try TestItem.init(allocator, 13, &deinit_count),
            try TestItem.init(allocator, 42, &deinit_count),
            try TestItem.init(allocator, 67, &deinit_count),
        };

        try list.appendSlice(appended[0..]);

        try expectTestItemIds(&list,&.{ 13, 42, 67 });
    }

    try testing.expectEqual(
        @as(usize, 3),
        deinit_count,
    );
}

test "ManagedDynamicBuffer init with slice and appendSlice" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        var initial = [_]TestItem{
            try TestItem.init(allocator, 13, &deinit_count),
            try TestItem.init(allocator, 42, &deinit_count),
            try TestItem.init(allocator, 67, &deinit_count),
        };

        var list = try TestItemList.init(allocator,initial[0..]);
        defer list.deinit();

        try expectTestItemIds(&list, &.{ 13, 42, 67 });

        var appended = [_]TestItem{
            try TestItem.init(allocator, 69, &deinit_count),
            try TestItem.init(allocator, 420, &deinit_count),
            try TestItem.init(allocator, 666, &deinit_count),
        };

        try list.appendSlice(appended[0..]);

        try expectTestItemIds(&list, &.{ 13, 42, 67, 69, 420, 666 });
    }

    try testing.expectEqual(@as(usize, 6),deinit_count);
}

test "ManagedDynamicBuffer set" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        const initial = try TestItem.init(allocator, 420, &deinit_count);
        const replacement = try TestItem.init(allocator, 67, &deinit_count);
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try testing.expectEqual(@as(usize, 0), list.len());

        try list.append(initial);
        try testing.expectEqual(@as(usize, 1), list.len());
        try testing.expectEqual(@as(usize, 420), (try list.get(0)).id);

        try list.set(0, replacement);
        try testing.expectEqual(@as(usize, 1), list.len());
        try testing.expectEqual(@as(usize, 67), (try list.get(0)).id);
    }
    try testing.expectEqual(@as(usize, 2), deinit_count);
}

test "ManagedDynamicBuffer set error" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    {
        var item = try TestItem.init(allocator, 67, &deinit_count);
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try testing.expectEqual(@as(usize, 0), list.len());

        try testing.expectError(ErrorSet.OutOfRange, list.set(1, item));
        item.deinit(allocator);
    }
    try testing.expectEqual(@as(usize, 1), deinit_count);    
}

test "ManagedDynamicBuffer pop" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    const item = try TestItem.init(allocator, 67, &deinit_count);
    var list = try TestItemList.init(allocator, null);
    defer list.deinit();

    try list.append(item);
    var popped = list.pop().?;

    try testing.expectEqual(@as(usize, 0), list.len());
    // pop shouldn't destroy the item
    try testing.expectEqual(@as(usize, 0), deinit_count);

    popped.deinit(allocator);
    try testing.expectEqual(@as(usize, 1), deinit_count);
}

test "ManagedDynamicBuffer toOwnedSlice" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;

    const items = [_]TestItem {
        try TestItem.init(allocator, 67, &deinit_count),
        try TestItem.init(allocator, 420, &deinit_count),
    };
    var list = try TestItemList.init(allocator, &items);
    defer list.deinit();

    try testing.expectEqual(@as(usize, 2), list.len());
    const owned = try list.toOwnedSlice();

    try testing.expectEqual(@as(usize, 0), list.len());
    try testing.expectEqual(@as(usize, 2), owned.len);

    // TestItemList doesn't own items anymore
    try testing.expectEqual(@as(usize, 0), deinit_count);
    for (owned) |*item| {
        item.deinit(allocator);
    }
    allocator.free(owned);
    try testing.expectEqual(@as(usize, 2), deinit_count);
}

const TestCallbackItem = struct {
    data: []u8,
    deinit_count: *usize,
    cb_deinit_count: *usize,

    pub fn deinit(self: *TestCallbackItem, alloc: std.mem.Allocator) void {
        alloc.free(self.data);
        self.deinit_count += 1;
        self.*= undefined;
    }
};

fn deinit_cb(alloc: std.mem.Allocator, item: *TestCallbackItem) void {
    alloc.free(item.data);
    item.cb_deinit_count.* += 1;
    item.* = undefined;
}

const TestCallbackItemList = ManagedDynamicBuffer(TestCallbackItem, deinit_cb);

test "ManagedDynamicBuffer with custom deinit callback" {
    const allocator = testing.allocator;
    var deinit_count: usize = 0;
    var cb_deinit_count: usize = 0;

    {
        var list = try TestCallbackItemList.init(allocator, null);
        defer list.deinit();

        try list.append(.{
            .data = try allocator.dupe(u8, "test"),
            .deinit_count = &deinit_count,
            .cb_deinit_count = &cb_deinit_count,
        });
    }
    // Ensure the callback was triggered instead of default deinit
    try testing.expectEqual(@as(usize, 0), deinit_count);
    try testing.expectEqual(@as(usize, 1), cb_deinit_count);
}

pub fn ManagedOpaqueWrapper(
    comptime Opaque: type,
    comptime Payload: type,
    comptime free_cb: fn(std.mem.Allocator, *Payload) void,
) type {
    return struct {
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
        ) ErrorSet!*Opaque {
            const ptr = alloc.create(Payload) catch {
                return ErrorSet.MemoryError;
            };
            ptr.* = val;
            return @ptrCast(ptr);
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
            const payload = unwrap(ptr);

            free_cb(alloc, payload);
            alloc.destroy(payload);
        }

        /// Converts opaque handler into internal mutable wrapper type.
        ///
        /// The pointer must be created with `create()` for this exact wrapper type.
        /// Passing wrong pointer results in undefined behaviour.
        pub fn unwrap(ptr: *Opaque) *Payload {
            return @ptrCast(@alignCast(ptr));
        }

        /// Converts opaque handler into internal immutable wrapper type.
        ///
        /// The pointer must be created with `create()` for this exact wrapper type.
        /// Passing wrong pointer results in undefined behaviour.
        pub fn unwrapConst(ptr: *const Opaque) *const Payload {
            return @ptrCast(@alignCast(ptr));
        }
    };
}

const TestOpaque = opaque {};
const TestPayload = struct {
    value: usize,
    freed: *bool,
};

fn freeTestPayloadCb(alloc: std.mem.Allocator, payload: *TestPayload) void {
    _ = alloc;
    payload.freed.* = true;
}

test "ManagedOpaqueWrapper should create, unwrap and destroy an opaque handler" {
    const allocator = testing.allocator;
    const ManagedTest = ManagedOpaqueWrapper(TestOpaque, TestPayload, freeTestPayloadCb);

    var freed = false;

    const wrapped = try ManagedTest.init(allocator, .{
        .value = 42,
        .freed = &freed,
    });

    const payload_mut = ManagedTest.unwrap(wrapped);
    try testing.expectEqual(@as(usize, 42), payload_mut.value);

    const payload_const = ManagedTest.unwrapConst(wrapped);
    try testing.expectEqual(@as(usize, 42), payload_const.value);

    ManagedTest.deinit(allocator, wrapped);
    try testing.expect(freed);
}

test "ManagedOpaque.deinit should not fail when passed null value" {
    const allocator = testing.allocator;
    const ManagedTest = ManagedOpaqueWrapper(TestOpaque, TestPayload, freeTestPayloadCb);

    ManagedTest.deinit(allocator, @as(?*TestOpaque, null));
}
