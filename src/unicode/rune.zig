const std = @import("std");
const types = @import("types");
const Error = types.Error;

pub const Rune = @This();

len: u4,
val: u21,

fn unicodeByteLen(value: u21) ?u4 {
    return switch(value) {
        0x0000...0x007F => 1,
        0x0080...0x07FF => 2,
        0x0800...0xFFFF => 3,
        0x1000...0x10FFFF => 4,
        else => null,
    };
}

pub fn from(value: u21) Error!Rune {
    const byte_length = unicodeByteLen(value) orelse {
        return Error.InvalidUnicode;
    };
    return Rune{
        .len = byte_length,
        .val = value,
    };
}

pub fn raw(self: Rune) u21 {
    return self.val;
}
