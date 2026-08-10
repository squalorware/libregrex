const types = @import("types");
const RegrexError = types.Error;
const tables = @import("./tables.zig");

fn unicodeByteLen(value: u21) ?u4 {
    return switch(value) {
        0x0000...0x007F => 1,
        0x0080...0x07FF => 2,
        0x0800...0xD7FF,
        0xE000...0xFFFF => 3,
        0x10000...0x10FFFF => 4,
        else => null,
    };
}

pub const Rune = struct {
    len: u4,
    val: u21,

    pub fn from(value: u21) RegrexError!Rune {
        const byte_length = unicodeByteLen(value) orelse {
            return RegrexError.InvalidUnicode;
        };
        return Rune{
            .len = byte_length,
            .val = value,
        };
    }

    pub fn raw(self: Rune) u21 {
        return self.val;
    }
};
