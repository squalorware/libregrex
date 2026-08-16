//! A decoded Unicode scalar value together with its byte length
const testing = @import("std").testing;
const Error = @import("types").Error;
const foldEqual = @import("./ranges.zig").foldEqual;

pub const Rune = @This();

/// Number of bytes required to encode the scalar as UTF-8
len: u4,
/// Unicode scalar value
val: u21,

/// Checks if the provided Unicode literal's numeric value
/// belongs within valid range of UTF-8 characters
/// and is not in the range of surrogates
pub fn byteLength(literal: u21) ?u4 {
    return switch(literal) {
        0x0000...0x007F => @as(u4, 1),
        0x0080...0x07FF => @as(u4, 2),
        0x0800...0xD7FF,
        0xE000...0xFFFF => @as(u4, 3),
        0x10000...0x10FFFF => @as(u4, 4),
        else => null,
    };
}

pub fn isLineBreak(self: Rune) bool {
    return switch(self.val) {
        '\n', '\r',
        0x2028, 0x2029 => true,
        else => false,
    };
}

/// Compares two Unicode scalar values according to regex case sensitivity flag
pub fn equals(self: Rune, to: u21, ignore_case: bool) bool {
    if (ignore_case) return foldEqual(self.val, to);
    return self.val == to;
}

/// Creates a Rune from a Unicode scalar literal
///
/// Returns `Error.InvalidUnicode` if value is outside of the Unicode range
/// or is a surrogate codepoint
pub fn from(literal: u21) Error!Rune {
    const byte_length = byteLength(literal) orelse return Error.InvalidUnicode;

    return Rune { .len = byte_length, .val = literal };
}

pub fn raw(self: Rune) u21 {
    return self.val;
}

test "Rune.from should correctly determine the UTF-8 byte length of given Unicode scalar" {
    try testing.expectEqual(
        @as(u4, 1),
        (try Rune.from(0x007F)).len,
    );

    try testing.expectEqual(
        @as(u4, 2),
        (try Rune.from(0x0080)).len,
    );

    try testing.expectEqual(
        @as(u4, 3),
        (try Rune.from(0x0800)).len,
    );

    try testing.expectEqual(
        @as(u4, 4),
        (try Rune.from(0x10000)).len,
    );
}

test "Rune.from should return an error for invalid Unicode scalars" {
    try testing.expectError(
        Error.InvalidUnicode,
        Rune.from(0xD800),
    );

    try testing.expectError(
        Error.InvalidUnicode,
        Rune.from(0xDFFF),
    );

    try testing.expectError(
        Error.InvalidUnicode,
        Rune.from(0x110000),
    );
}

test "Rune.raw should return the original scalar value" {
    const rune = try Rune.from(0x1F600);

    try testing.expectEqual(
        @as(u21, 0x1F600),
        rune.raw(),
    );
}

