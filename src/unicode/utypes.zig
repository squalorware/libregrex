const Error = @import("types").Error;

pub const SearchOrder = enum {
    /// The key occurs before the current item
    before,
    /// The current item matches the key
    match,
    /// The key occurs after the current item
    after,
};

pub const CompareMode = enum {
    range,
    case_fold,
};

pub const RunePair = struct {
    start: u21,
    end: u21,

    pub fn compare(low: u21, high: u21, rune: u21) SearchOrder {
        if (rune < low) return .before;
        if (rune > high) return .after;

        return .match;
    }
};

pub const RuneTable = struct {
    unicode_version: []const u8,
    digit_ranges: []const RunePair,
    word_ranges: []const RunePair,
    whitespace_ranges: []const RunePair,
    case_folds: []const RunePair,
};

pub const RuneClass = enum {
    digit,
    word,
    whitespace,
};

pub const Rune = struct {
    len: u4,
    val: u21,

    pub fn from(literal: u21) Error!Rune {
        const byte_length = switch(literal) {
            0x0000...0x007F => @as(u4, 1),
            0x0080...0x07FF => @as(u4, 2),
            0x0800...0xD7FF,
            0xE000...0xFFFF => @as(u4, 3),
            0x10000...0x10FFFF => @as(u4, 4),
            else => null,
        } orelse return Error.InvalidUnicode;

        return Rune { .len = byte_length, .val = literal };
    }

    pub fn raw(self: Rune) u21 {
        return self.val;
    }
};
