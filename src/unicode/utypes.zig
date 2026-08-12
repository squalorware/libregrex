const testing = @import("std").testing;
const Error = @import("types").Error;

/// Results of comparing a Unicode character against the lookup table
pub const SearchOrder = enum {
    /// The key occurs before the current item
    before,
    /// The current item matches the key
    match,
    /// The key occurs after the current item
    after,
};

/// Determines if a `RunePair` is compared as a range or as a case-fold mapping
pub const CompareMode = enum {
    /// .start and .end delimit an inclusive Unicode codepoint range
    range,
    /// .start is a source codepoint in a case-fold mapping; .end is a target
    case_fold,
};

/// An entry from the lookup table containing a pair of Unicode codepoints
///
/// Can represent both a character class range and a simple case-fold mapping
pub const RunePair = struct {
    start: u21,
    end: u21,

    /// Compares given scalar against an inclusive range `[low..high]`
    pub fn compare(low: u21, high: u21, rune: u21) SearchOrder {
        if (rune < low) return .before;
        if (rune > high) return .after;

        return .match;
    }
};

/// The lookup table representation
///
/// Contains Unicode character-class ranges and 1-to-1 simple case-fold mappings
/// from the Unicode Character Database of specific version, recorded by `unicode_version`
///
/// Provides typing for data loaded from the generated `rune_table.zon` file;
/// See `tools/download_ucd_tables.py`
pub const RuneTable = struct {
    unicode_version: []const u8,
    digit_ranges: []const RunePair,
    word_ranges: []const RunePair,
    whitespace_ranges: []const RunePair,
    case_folds: []const RunePair,
};

/// Preset Unicode character classes
pub const RuneClass = enum {
    /// Decimal numeric characters
    digit,
    /// Alphabetical characters
    word,
    /// Whitespace characters
    whitespace,
};

/// A decoded Unicode scalar value together with its byte length
pub const Rune = struct {
    /// Number of bytes required to encode the scalar as UTF-8
    len: u4,
    /// Unicode scalar value
    val: u21,

    /// Creates a Rune from a Unicode scalar literal
    ///
    /// Returns `Error.InvalidUnicode` if value is outside of the Unicode range
    /// or is a surrogate codepoint
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

    /// Returns the raw scalar value represented by this Rune
    pub fn raw(self: Rune) u21 {
        return self.val;
    }
};

test "RunePair.compare should compare Rune against an inclusive range" {
    try testing.expectEqual(
        SearchOrder.before,
        RunePair.compare(10, 20, 9),
    );

    try testing.expectEqual(
        SearchOrder.match,
        RunePair.compare(10, 20, 10),
    );

    try testing.expectEqual(
        SearchOrder.match,
        RunePair.compare(10, 20, 15),
    );

    try testing.expectEqual(
        SearchOrder.match,
        RunePair.compare(10, 20, 20),
    );

    try testing.expectEqual(
        SearchOrder.after,
        RunePair.compare(10, 20, 21),
    );
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
