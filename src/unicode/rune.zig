const std = @import("std");
const types = @import("types");
const Error = types.Error;

pub const Rune = packed struct {
    len: u4,
    val: u21,

    pub fn from(value: u21) Error!Rune {
        return .{
            .len = try utf8ByteLen(value),
            .val = value,
        };
    }

    pub fn raw(self: Rune) u21 {
        return self.val;
    }

    fn utf8ByteLen(value: u21) Error!u4 {
        return switch(value) {
            0x0000...0x007F => 1,
            0x0080...0x07FF => 2,
            0x0800...0xFFFF => 3,
            0x10000...0x10FFFF => 4,
            else => Error.InvalidUnicode,
        };
    }
};
