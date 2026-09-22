//! Generics and meta-programming
//! All generic and/or comptime types and functions are prefixed with `T_`
const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const misc = @import("./misc.zig");
const Type = std.builtin.Type;
const StructField = Type.StructField;
const Attributes = Type.StructField.Attributes;
const LookupOrder = misc.LookupOrder;
const RangeOptions = misc.RangeOptions;

pub fn is(comptime Id: std.builtin.TypeId) fn (type) bool {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            return Id == @typeInfo(T);
        }
    };
    return Closure.trait;
}


pub fn hasDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "deinit"),
        else => false,
    };
}

pub fn hasLength(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .array => true,
        .pointer => @hasDecl(T, "len"),
        else => false,
    };
}

pub fn isSlice(comptime T: type) bool {
    if (is(.pointer)(T) and hasLength(T)) {
        return true;
    }
    return false;
}


/// Checks if `name` is unique as `field.name for field in fields`
pub fn uniq(comptime fields: []const StructField, name: []const u8) bool {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return false;
    }
    return true;
}

/// Retrieves the index of a field by its name from the array of struct fields
pub fn fieldIndex(comptime fields: []const StructField, name: []const u8) ?usize {
    for (fields, 0..) |field, i| {
        if (std.mem.eql(u8, field.name, name)) {
            return i;
        }
    }
    return null;
}

/// Merges two integer types adding up their bit sizes
///
/// The signedness of new integer type depends on whichever of two is wider
pub fn T_MergedInt(comptime T_BaseInt: type, comptime T_ExtraInt: type) type {
    const first = @typeInfo(T_BaseInt).int;
    const second = @typeInfo(T_ExtraInt).int;

    const bits: u16 = first.bits + second.bits;
    // The sign is determined by whichever of the two has
    // a wider bit range to hold positive values
    // e.g. if `T_BaseInt` is u16, and `T_ExtraInt` is i8, the result will be u24
    const sign = if (first.bits > second.bits)
        first.signedness
            // T_BaseInt (u8) + T_ExtraInt (i16) = i24
    else if (second.bits > first.bits)
        second.signedness
            // If bits are equal but any of the pair is unsigned, then result is unsigned
    else if (first.signedness == .unsigned or second.signedness == .unsigned)
        std.builtin.Signedness.unsigned
            // Exhausted all options; both integers must be signed so result is signed
    else
        std.builtin.Signedness.signed;

    return @Int(sign, bits);
}

/// Merges two generic structs into one
///
/// Merges only structure fields. Does not copy functions or associated variables.
/// If a field in `T_Extra` has the same name as one already copied from `T_Base` it is skipped.
///
/// Creates a packed struct with an extended backing integer if both `T_Base` and `T_Extra` are packed
pub fn T_MergedStruct(comptime T_Base: type, comptime T_Extra: type) type {
    const base_t = @typeInfo(T_Base).@"struct";
    const extra_t = @typeInfo(T_Extra).@"struct";
    const both_packed =
        base_t.layout == .@"packed" and
        extra_t.layout == .@"packed";

    // Unique field counter
    comptime var ufc: usize = base_t.fields.len;
    // Count unique fields in Extra
    inline for (extra_t.fields) |field| {
        if (uniq(base_t.fields, field.name)) ufc += 1;
    }

    comptime var names: [ufc][]const u8 = undefined;
    comptime var types: [ufc]type = undefined;
    comptime var attrs: [ufc]Attributes = undefined;

    // Copy counter
    var i: usize = 0;
    // `T_Base` takes precedence; its fields are copied first so are assumed unique by default
    inline for (base_t.fields) |field| {
        names[i] = field.name;
        types[i] = field.type;
        attrs[i] = @as(Attributes, .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        });
        i += 1;
    }
    // Deduplicate and copy fields from `T_Extra`
    inline for (extra_t.fields) |field| {
        const is_dup = !uniq(base_t.fields, field.name);
        const is_padding = std.mem.eql(u8, field.name, "_padding");

        // Padding is present in both types; layout of both must be packed
        // Merge T_Extra._padding with copied from T_Base
        if (is_dup and is_padding) {
            // Get index of ._padding in Base
            if (fieldIndex(base_t.fields, "_padding")) |base_i| {
                const base_pad = base_t.fields[base_i];
                const T_Padding = T_MergedInt(base_pad.type, field.type);

                types[base_i] = T_Padding;
                attrs[base_i] = .{
                    .@"comptime" = field.is_comptime,
                    .@"align" = null,
                    .default_value_ptr = &@as(T_Padding, 0),
                };
            }
            continue;
            // Skip other duplicates
        } else if (is_dup) continue;

        names[i] = field.name;
        types[i] = field.type;
        attrs[i] = @as(Attributes, .{
            .@"comptime" = field.is_comptime,
            .@"align" = field.alignment,
            .default_value_ptr = field.default_value_ptr,
        });
        i += 1;
    }

    const layout: Type.ContainerLayout = if (both_packed) .@"packed" else .auto;
    const backing_int: ?type = if (both_packed) T_MergedInt(
        base_t.backing_integer.?,
        extra_t.backing_integer.?,
    ) else null;

    return @Struct(layout, backing_int, &names, &types, &attrs);
}

/// Generic representation of a range offset
///
/// `T` must be an integer type, otherwise compilation fails; accepts optional flag
/// to create a structure with C-compatible memory layout (default: false)
pub fn T_Range(comptime T: type, opts: RangeOptions) type {
    const info = @typeInfo(T);

    if (info != .int) {
        @compileError("Offset type is not integer");
    }

    if (opts.extern_compat and !std.math.isPowerOfTwo(info.int.bits)) {
        @compileError("Cannot create extern Range: integer bit size is not compatible");
    }
    // duplicated doc comment because we return two distinct structs
    // so we want to ensure that LSP picks up docs for either
    if (opts.extern_compat) {
        return extern struct {
            const Self = @This();

            start: T,
            end: T,
            /// Compares an integer `T` against an inclusive range `[tail..head]` of same type
            pub fn compare(tail: T, head: T, item: T) LookupOrder {
                if (item < tail) return .before;
                if (item > head) return .after;

                return .match;
            }

            /// Checks if given item exists within this range
            pub fn contains(self: Self, item: T) bool {
                return compare(self.start, self.end, item) == .match;
            }
        };
    }
    return struct {
        const Self = @This();

        start: T,
        end: T,
        /// Compares an integer `T` against an inclusive range `[tail..head]` of same type
        pub fn compare(tail: T, head: T, item: T) LookupOrder {
            if (item < tail) return .before;
            if (item > head) return .after;

            return .match;
        }

        /// Checks if given item exists within this range
        pub fn contains(self: Self, item: T) bool {
            return compare(self.start, self.end, item) == .match;
        }
    };
}

/// Generic destructor callback
pub fn T_DestructorCallback(comptime T: type) type {
    return *const fn (std.mem.Allocator, *T) void;
}

/// Generic wrapper over a closure function
///
/// Allows interfacing between two types without one explicitly being a field of another
pub fn T_Closure(comptime T: type, comptime O: type, comptime R: type) type {
    return *const fn (ctx: *const T, opts: O) ErrorSet!R;
}

/// Creates a proxy interface between an external opaque and an internal structs
pub fn T_OpaqueInterface(comptime T: type, comptime OT: type, destroy_cb: ?T_DestructorCallback(T)) type {
    return struct {
        const destroyCallback = destroy_cb;

        pub fn create(alloc: std.mem.Allocator, m: ?T) ErrorSet!*OT {
            const internal = m orelse return ErrorSet.InvalidArgument;

            const ptr: *T = alloc.create(T) catch return ErrorSet.MemoryError;
            ptr.* = internal;

            return @ptrCast(ptr);
        }

        pub fn destroy(self: ?*OT, alloc: std.mem.Allocator) void {
            const op = self orelse return;
            const ptr = unwrap(op) catch return;

            if (destroy_cb) |func| func(alloc, ptr);
            alloc.destroy(ptr);
        }

        pub fn unwrap(self: ?*OT) ErrorSet!*T {
            const ptr = self orelse return ErrorSet.InvalidArgument;
            return @ptrCast(@alignCast(ptr));
        }

        pub fn unwrapConst(self: ?*OT) ErrorSet!*const T {
            const ptr = self orelse return ErrorSet.InvalidArgument;
            return @ptrCast(@alignCast(ptr));
        }
    };
}

/// Wraps over `std.ArrayList` allowing it owning values it stores.
///
/// Released with `Self.deinit` using allocator saved on initializing.
/// If stored items need explicit deinit, optional `destroy_cb` must receive
/// `*const fn(std.mem.Allocator, *T) void` when the wrapper is called to create a list.
pub fn T_ManagedArrayList(
    comptime T: type,
    destroy_cb: ?T_DestructorCallback(T),
) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        inner: std.ArrayList(T),

        /// If buffer is supplied, the values are copied to the list which takes ownership of them
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

        fn deinitItem(self: Self, item: *T) void {
            if (destroy_cb) |callback| {
                callback(self.allocator, item);
            } else if (comptime hasDeinit(T)) {
                item.deinit(self.allocator);
            }
        }

        /// Releases all owned values before the backing array
        pub fn deinit(self: *Self) void {
            for (self.inner.items) |*item| {
                self.deinitItem(item);
            }

            self.inner.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn contains(self: Self, item: T) bool {
            for (self.inner.items) |elem| {
                if (isSlice(T)) {
                    return std.mem.eql(T, elem, item);
                } else {
                    return elem == item;
                }
            }
        }

        /// If allocation fails, releases the `item` before returning an error
        pub fn append(self: *Self, item: T) ErrorSet!void {
            var owned = item;

            self.inner.append(self.allocator, owned) catch {
                self.deinitItem(&owned);
                return ErrorSet.MemoryError;
            };
        }

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

        /// Returns a borrowed pointer to the value at `i`
        ///
        /// Returns `Error.InvalidArgument` if `i` is outside the list.
        pub fn get(self: *const Self, i: usize) ErrorSet!*const T {
            if (i >= self.inner.items.len) {
                return ErrorSet.InvalidArgument;
            }

            return &self.inner.items[i];
        }

        /// Replaces the value at `i`
        ///
        /// Releases the previous value and takes ownership of `val` on success.
        /// If `i` is invalid, ownership of `val` remains with the caller.
        pub fn set(self: *Self, i: usize, val: T) ErrorSet!void {
            if (i >= self.inner.items.len) {
                return ErrorSet.OutOfRange;
            }

            self.deinitItem(&self.inner.items[i]);
            self.inner.items[i] = val;
        }

        /// Transfers ownership of returned value to the caller.
        pub fn pop(self: *Self) ?T {
            return self.inner.pop();
        }

        /// Transfers ownership of returned slice and its items to the caller
        pub fn toOwnedSlice(self: *Self) ErrorSet![]T {
            return self.inner.toOwnedSlice(self.allocator) catch {
                return ErrorSet.MemoryError;
            };
        }
    };
}

pub fn freeAlloc(comptime T: type, alloc: std.mem.Allocator, sequence: []T, destroy_cb: ?T_DestructorCallback(T)) void {
    if (destroy_cb) |callback| {
        for (sequence) |*item| {
            callback(alloc, item);
        }
    }    

    alloc.free(sequence);
}

test "MergeInt merges two integer types into new one with combined bit size" {
    const base = u4;
    const extra = u8;

    const expected = @typeInfo(base).int.bits + @typeInfo(extra).int.bits;

    const my_int = T_MergedInt(base, extra);
    const info = @typeInfo(my_int).int;

    try std.testing.expectEqual(expected, info.bits);
    try std.testing.expectEqual(std.builtin.Signedness.unsigned, info.signedness);
}

test "MergeInt merges to the sign of the one with wider bit size" {
    var expected: u16 = 0;

    {
        const base = u16;
        const extra = i8;

        expected = @typeInfo(base).int.bits + @typeInfo(extra).int.bits;

        const my_int = T_MergedInt(base, extra);
        const info = @typeInfo(my_int).int;

        try std.testing.expectEqual(expected, info.bits);
        try std.testing.expectEqual(std.builtin.Signedness.unsigned, info.signedness);
    }
    expected = 0;

    {
        const base = u8;
        const extra = i16;

        expected = @typeInfo(base).int.bits + @typeInfo(extra).int.bits;

        const my_int = T_MergedInt(base, extra);
        const info = @typeInfo(my_int).int;

        try std.testing.expectEqual(expected, info.bits);
        try std.testing.expectEqual(std.builtin.Signedness.signed, info.signedness);
    }
}

test "MergeInt merges equal bit sizes to unsigned if signs differ" {
    const base = u8;
    const extra = i8;

    const expected = @typeInfo(base).int.bits + @typeInfo(extra).int.bits;

    const my_int = T_MergedInt(base, extra);
    const info = @typeInfo(my_int).int;

    try std.testing.expectEqual(expected, info.bits);
    try std.testing.expectEqual(std.builtin.Signedness.unsigned, info.signedness);
}

test "MergeInt merges two signed to signed" {
    const base = i8;
    const extra = i8;

    const expected = @typeInfo(base).int.bits + @typeInfo(extra).int.bits;

    const my_int = T_MergedInt(base, extra);
    const info = @typeInfo(my_int).int;

    try std.testing.expectEqual(expected, info.bits);
    try std.testing.expectEqual(std.builtin.Signedness.signed, info.signedness);
}

test "MergedStruct merges two regular structs" {
    const Foo = struct {
        foo: u8 = 1,
        bar: bool = false,
    };

    const Bar = struct {
        baz: u16 = 2,
        qux: i32 = -1,
    };

    const Merged = T_MergedStruct(Foo, Bar);
    const info = @typeInfo(Merged).@"struct";

    try std.testing.expectEqual(Type.ContainerLayout.auto, info.layout);

    try std.testing.expectEqual(@as(usize, 4), info.fields.len);

    try std.testing.expectEqualStrings("foo", info.fields[0].name);
    try std.testing.expectEqual(u8, info.fields[0].type);

    try std.testing.expectEqualStrings("bar", info.fields[1].name);
    try std.testing.expectEqual(bool, info.fields[1].type);

    try std.testing.expectEqualStrings("baz", info.fields[2].name);
    try std.testing.expectEqual(u16, info.fields[2].type);

    try std.testing.expectEqualStrings("qux", info.fields[3].name);
    try std.testing.expectEqual(i32, info.fields[3].type);

    const value: Merged = .{};

    try std.testing.expectEqual(@as(u8, 1), value.foo);
    try std.testing.expectEqual(false, value.bar);
    try std.testing.expectEqual(@as(u16, 2), value.baz);
    try std.testing.expectEqual(@as(i32, -1), value.qux);
}

test "MergedStruct keeps Foo version of duplicate fields" {
    const Foo = struct {
        shared: u8 = 42,
        foo: bool = true,
    };

    const Bar = struct {
        shared: u64 = 9000,
        bar: u16 = 7,
    };

    const Merged = T_MergedStruct(Foo, Bar);
    const info = @typeInfo(Merged).@"struct";

    try std.testing.expectEqual(@as(usize, 3), info.fields.len);

    try std.testing.expectEqualStrings("shared", info.fields[0].name);
    try std.testing.expectEqual(u8, info.fields[0].type);

    try std.testing.expectEqualStrings("foo", info.fields[1].name);
    try std.testing.expectEqualStrings("bar", info.fields[2].name);

    const value: Merged = .{};

    try std.testing.expectEqual(@as(u8, 42), value.shared);
    try std.testing.expectEqual(true, value.foo);
    try std.testing.expectEqual(@as(u16, 7), value.bar);
}

test "MergedStruct merges two packed structs" {
    const Foo = packed struct(u3) {
        foo: bool = false,
        _padding: u2 = 0,
    };

    const Bar = packed struct(u5) {
        bar: bool = false,
        baz: bool = false,
        _padding: u3 = 0,
    };

    const Merged = T_MergedStruct(Foo, Bar);
    const info = @typeInfo(Merged).@"struct";

    try std.testing.expectEqual(
        Type.ContainerLayout.@"packed",
        info.layout,
    );

    try std.testing.expectEqual(u8, info.backing_integer.?);
    try std.testing.expectEqual(
        @as(usize, 4),
        info.fields.len,
    );

    try std.testing.expectEqualStrings("foo", info.fields[0].name);
    try std.testing.expectEqual(bool, info.fields[0].type);

    try std.testing.expectEqualStrings("_padding", info.fields[1].name);
    try std.testing.expectEqual(u5, info.fields[1].type);

    try std.testing.expectEqualStrings("bar", info.fields[2].name);
    try std.testing.expectEqual(bool, info.fields[2].type);

    try std.testing.expectEqualStrings("baz", info.fields[3].name);
    try std.testing.expectEqual(bool, info.fields[3].type);

    try std.testing.expectEqual(@as(usize, 8), @bitSizeOf(Merged));

    const value: Merged = .{
        .foo = true,
        .bar = false,
        .baz = true,
    };

    try std.testing.expect(value.foo);
    try std.testing.expect(!value.bar);
    try std.testing.expect(value.baz);
    try std.testing.expectEqual(@as(u5, 0), value._padding);
}

const TestItem = struct {
    id: usize,
    data: []u8,
    deinit_count: *usize,

    pub fn init(alloc: std.mem.Allocator, id: usize, deinit_count: *usize) !TestItem {
        return .{ .id = id, .data = try alloc.dupe(u8, "test"), .deinit_count = deinit_count };
    }

    pub fn deinit(self: *TestItem, alloc: std.mem.Allocator) void {
        _ = alloc.free(self.data);
        self.deinit_count.* += 1;
        self.* = undefined;
    }
};

const TestItemList = T_ManagedArrayList(TestItem, null);

fn expectTestItemIds(list: *const TestItemList, expected: []const usize) !void {
    try std.testing.expectEqual(expected.len, list.len());

    for (expected, 0..) |expected_id, i| {
        try std.testing.expectEqual(
            expected_id,
            (try list.get(i)).id,
        );
    }
}

test "ManagedArrayList init empty and append" {
    const allocator = std.testing.allocator;
    var deinit_count: usize = 0;

    {
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try std.testing.expectEqual(@as(usize, 0), list.len());

        const item = try TestItem.init(
            allocator,
            67,
            &deinit_count,
        );

        try list.append(item);

        try expectTestItemIds(&list, &.{67});
    }

    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

test "ManagedArrayList init with slice and append" {
    const allocator = std.testing.allocator;
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

    try std.testing.expectEqual(@as(usize, 4), deinit_count);
}

test "ManagedArrayList init empty and appendSlice" {
    const allocator = std.testing.allocator;
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

        try expectTestItemIds(&list, &.{ 13, 42, 67 });
    }

    try std.testing.expectEqual(
        @as(usize, 3),
        deinit_count,
    );
}

test "ManagedArrayList init with slice and appendSlice" {
    const allocator = std.testing.allocator;
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

        var appended = [_]TestItem{
            try TestItem.init(allocator, 69, &deinit_count),
            try TestItem.init(allocator, 420, &deinit_count),
            try TestItem.init(allocator, 666, &deinit_count),
        };

        try list.appendSlice(appended[0..]);

        try expectTestItemIds(&list, &.{ 13, 42, 67, 69, 420, 666 });
    }

    try std.testing.expectEqual(@as(usize, 6), deinit_count);
}

test "ManagedArrayList set" {
    const allocator = std.testing.allocator;
    var deinit_count: usize = 0;

    {
        const initial = try TestItem.init(allocator, 420, &deinit_count);
        const replacement = try TestItem.init(allocator, 67, &deinit_count);
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try std.testing.expectEqual(@as(usize, 0), list.len());

        try list.append(initial);
        try std.testing.expectEqual(@as(usize, 1), list.len());
        try std.testing.expectEqual(@as(usize, 420), (try list.get(0)).id);

        try list.set(0, replacement);
        try std.testing.expectEqual(@as(usize, 1), list.len());
        try std.testing.expectEqual(@as(usize, 67), (try list.get(0)).id);
    }
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

test "ManagedArrayList set error" {
    const allocator = std.testing.allocator;
    var deinit_count: usize = 0;

    {
        var item = try TestItem.init(allocator, 67, &deinit_count);
        var list = try TestItemList.init(allocator, null);
        defer list.deinit();

        try std.testing.expectEqual(@as(usize, 0), list.len());

        try std.testing.expectError(ErrorSet.OutOfRange, list.set(1, item));
        item.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

test "ManagedArrayList pop" {
    const allocator = std.testing.allocator;
    var deinit_count: usize = 0;

    const item = try TestItem.init(allocator, 67, &deinit_count);
    var list = try TestItemList.init(allocator, null);
    defer list.deinit();

    try list.append(item);
    var popped = list.pop().?;

    try std.testing.expectEqual(@as(usize, 0), list.len());
    // pop shouldn't destroy the item
    try std.testing.expectEqual(@as(usize, 0), deinit_count);

    popped.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), deinit_count);
}

test "ManagedArrayList toOwnedSlice" {
    const allocator = std.testing.allocator;
    var deinit_count: usize = 0;

    var initial = [_]TestItem{
        try TestItem.init(allocator, 67, &deinit_count),
        try TestItem.init(allocator, 420, &deinit_count),
    };
    var list = try TestItemList.init(allocator, initial[0..]);
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 2), list.len());
    const owned = try list.toOwnedSlice();

    try std.testing.expectEqual(@as(usize, 0), list.len());
    try std.testing.expectEqual(@as(usize, 2), owned.len);

    // TestItemList doesn't own items anymore
    try std.testing.expectEqual(@as(usize, 0), deinit_count);
    for (owned) |*item| {
        item.deinit(allocator);
    }
    _ = allocator.free(owned);
    try std.testing.expectEqual(@as(usize, 2), deinit_count);
}

const TestCallbackItem = struct {
    data: []u8,
    deinit_count: *usize,
    cb_deinit_count: *usize,

    pub fn deinit(self: *TestCallbackItem, alloc: std.mem.Allocator) void {
        _ = alloc.free(self.data);
        self.deinit_count += 1;
        self.* = undefined;
    }
};

fn deinit_cb(alloc: std.mem.Allocator, item: ?*TestCallbackItem) void {
    const elem = item orelse return;
    _ = alloc.free(elem.data);
    elem.cb_deinit_count.* += 1;
    elem.* = undefined;
}

const TestCallbackItemList = T_ManagedArrayList(TestCallbackItem, deinit_cb);

test "ManagedArrayList with custom deinit callback" {
    const allocator = std.testing.allocator;
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
    try std.testing.expectEqual(@as(usize, 0), deinit_count);
    try std.testing.expectEqual(@as(usize, 1), cb_deinit_count);
}
