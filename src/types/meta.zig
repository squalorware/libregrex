const std = @import("std");
const Type = std.builtin.Type;
const StructField = Type.StructField;
const Attributes = Type.StructField.Attributes;

/// Checks if `name` is unique as `field.name for field in fields`
fn uniq(comptime fields: []const StructField, name: []const u8) bool {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return false;
    }
    return true;
}

/// Retrieves the index of a field by its name from the array of struct fields
fn fieldIndex(comptime fields: []const StructField, name: []const u8) ?usize {
    for (fields, 0..) |field, i| {
        if (std.mem.eql(u8, field.name, name)) {
            return i;
        }
    }
    return null;
}

/// Merges two integer types creating a new one
///
/// The signedness of new integer type depends on whichever of two is wider.
/// The bit size is first and second bits combined.
pub fn MergedInt(comptime First: type, comptime Second: type) type {
    const first = @typeInfo(First).int;
    const second = @typeInfo(Second).int;

    const bits: u16 = first.bits + second.bits;
    const sign = if (first.bits > second.bits)
        first.signedness
    else if (second.bits > first.bits)
            second.signedness
        else if (first.signedness == .unsigned or second.signedness == .unsigned)
                std.builtin.Signedness.unsigned
            else
                std.builtin.Signedness.signed;

    return @Int(sign, bits);
}

/// Merges two generic structs into one.
///
/// Merges only `struct` fields.
/// Does not copy member functions or associated constants.
/// Fields are deduplicated during copying - `Foo` acts as a base;
/// `Bar` fields are checked for uniqueness against it. Any field from `Bar` that
/// shares the name with one from `Foo` is discarded
/// (except `"_padding"` which might be useful for creating packed structs).
///
/// The created type is a regular unpacked struct by default.
/// If either of types is packed, while other is unpacked, its `BackingInt` is discarded.
/// If both structures' layout is packed, a new `packed struct` is created,
/// with input types' backing integers and paddings merged.
pub fn MergedStruct(comptime Foo: type, comptime Bar: type) type {
    comptime {
        const foo_struct = @typeInfo(Foo).@"struct";
        const bar_struct = @typeInfo(Bar).@"struct";
        const both_packed =
            foo_struct.layout == .@"packed" and
                bar_struct.layout == .@"packed";

        // Unique field counter. Treat Foo as base
        var ufc: usize = foo_struct.fields.len;
        // Count unique fields in Bar
        for (bar_struct.fields) |field| {
            if (uniq(foo_struct.fields, field.name)) ufc += 1;
        }

        var names: [ufc][]const u8 = undefined;
        var types: [ufc]type = undefined;
        var attrs: [ufc]Attributes = undefined;

        // Copy counter
        var i: usize = 0;
        // Copy base fields from Foo
        for (foo_struct.fields) |field| {
            names[i] = field.name;
            types[i] = field.type;
            attrs[i] = @as(Attributes, .{
                .@"comptime" = field.is_comptime,
                .@"align" = field.alignment,
                .default_value_ptr = field.default_value_ptr,
            });
            i += 1;
        }
        // Copy unique fields from Bar
        for (bar_struct.fields) |field| {
            const is_dup = !uniq(foo_struct.fields, field.name);
            const is_padding = std.mem.eql(u8, field.name, "_padding");

            if (is_dup and is_padding) {
                if (fieldIndex(foo_struct.fields, "_padding")) |foo_i| {
                    const foo_pad = foo_struct.fields[foo_i];
                    const PaddingType = MergedInt(foo_pad.type, field.type);
                    // Padding is present in both types; extend copied from base
                    types[foo_i] = PaddingType;
                    attrs[foo_i] = .{
                        .@"comptime" = field.is_comptime,
                        .@"align" = null,
                        .default_value_ptr = &@as(PaddingType, 0),
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

        // Create a packed struct with an extended backing integer if both structs were packed
        const layout: Type.ContainerLayout = if (both_packed) .@"packed" else .auto;
        const backing_int: ?type = if (both_packed) MergedInt(
            foo_struct.backing_integer.?,
            bar_struct.backing_integer.?,
        ) else null;

        return @Struct(layout, backing_int, &names, &types, &attrs);
    }
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

    const Merged = MergedStruct(Foo, Bar);
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

    const Merged = MergedStruct(Foo, Bar);
    const info = @typeInfo(Merged).@"struct";

    try std.testing.expectEqual(@as(usize, 3), info.fields.len);

    try std.testing.expectEqualStrings("shared", info.fields[0].name);
    try std.testing.expectEqual(u8, info.fields[0].type);

    try std.testing.expectEqualStrings("foo", info.fields[1].name);
    try std.testing.expectEqualStrings("bar",info.fields[2].name);

    const value: Merged = .{};

    try std.testing.expectEqual(@as(u8, 42), value.shared);
    try std.testing.expectEqual(true, value.foo);
    try std.testing.expectEqual(@as(u16, 7),value.bar);
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

    const Merged = MergedStruct(Foo, Bar);
    const info = @typeInfo(Merged).@"struct";

    try std.testing.expectEqual(
        Type.ContainerLayout.@"packed",
        info.layout,
    );

    try std.testing.expectEqual(u8,info.backing_integer.?);
    try std.testing.expectEqual(
        @as(usize, 4),
        info.fields.len,
    );

    try std.testing.expectEqualStrings("foo",info.fields[0].name);
    try std.testing.expectEqual(bool,info.fields[0].type);

    try std.testing.expectEqualStrings("_padding",info.fields[1].name);
    try std.testing.expectEqual(u5,info.fields[1].type);

    try std.testing.expectEqualStrings("bar",info.fields[2].name);
    try std.testing.expectEqual(bool,info.fields[2].type);

    try std.testing.expectEqualStrings("baz", info.fields[3].name);
    try std.testing.expectEqual(bool,info.fields[3].type);

    try std.testing.expectEqual(@as(usize, 8),@bitSizeOf(Merged));

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