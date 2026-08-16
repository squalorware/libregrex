const testing = @import("std").testing;
const Error = @import("types").Error;

const LookupOrder = enum {
    before,
    match,
    after,
};

pub const CharClassType = enum {
    digit,
    word,
    whitespace,
};

pub const RuneRangeType = enum {
    char_class,
    case_fold,
};

pub const RuneRange = struct {
    start: u21,
    end: u21,

    /// Compares given scalar against an inclusive range `[low..high]`
    pub fn compare(low: u21, high: u21, literal: u21) LookupOrder {
        if (literal < low) return .before;
        if (literal > high) return .after;

        return .match;
    }

    /// Checks whether `literal` occurs within this inclusive range.
    pub fn contains(self: RuneRange, literal: u21) bool {
        return compare(self.start, self.end, literal) == .match;
    }
};

/// The lookup table representation
///
/// Contains Unicode character-class ranges and 1-to-1 simple case-fold mappings
/// from the Unicode Character Database of specific version, recorded by `unicode_version`
///
/// Provides typing for data loaded from the generated `unicode/data/ucd_tables.zon` file;
/// See `tools/download_ucd_tables.py`
pub const RuneTable: struct {
    unicode_version: []const u8,
    digit_ranges: []const RuneRange,
    word_ranges: []const RuneRange,
    whitespace_ranges: []const RuneRange,
    case_folds: []const RuneRange,
} = @import("./data/ucd_tables.zon");

/// Compares a Unicode codepoint against the lookup table
///
/// `as` controls whether it is compared as a character class
///  or as a case-fold mapping
///
/// Returns the position of the scalar relative to the specified range
fn compareWithRange(rune: u21, range: RuneRange, as: RuneRangeType) LookupOrder {
    return switch(as) {
        .char_class => RuneRange.compare(range.start, range.end, rune),
        .case_fold => RuneRange.compare(range.start, range.start, rune),
    };
}

/// Searches the scalar codepoint in the sorted lookup table
///
/// If `mode` is `CompareMode.range` the key is matched against
/// the inclusive `start..end` range of each item in `items`
///
/// If `mode` is `CompareMode.case_fold` uses only `item.start` as a lookup key
fn binarySearch(items: []const RuneRange, key: u21, mode: RuneRangeType) ?*const RuneRange {
    var low: usize = 0;
    var high: usize = items.len;

    while (low < high) {
        const mid = low + (high - low) / 2;

        switch (compareWithRange(key, items[mid], mode)) {
            .before => high = mid,
            .after => low = mid + 1,
            .match => return &items[mid],
        }
    }
    return null;
}

/// Checks if Rune occurs within given character class
fn charClassContains(class: []const RuneRange, literal: u21) bool {
    return binarySearch(class, literal, RuneRangeType.char_class) != null;
}

/// Checks if given literal belongs to one of the preset character classes
pub fn isInClass(cls: CharClassType, literal: u21) bool {
    return switch(cls) {
        .digit => charClassContains(RuneTable.digit_ranges, literal),
        .word => charClassContains(RuneTable.word_ranges, literal),
        .whitespace => charClassContains(RuneTable.whitespace_ranges, literal),
    };
}

/// Searches for a simple Unicode case-fold mapping
/// for given UTF-8 literal in the lookup table
///
/// If literal has no correspondent mapping returns it unchanged
pub fn simpleCaseFold(literal: u21) u21 {
    const map = binarySearch(
        RuneTable.case_folds[0..],
        literal,
        RuneRangeType.case_fold
    ) orelse return literal;

    return map.end;
}

/// Checks the case-folding of two characters
/// (if mapping exists, given scalars are different cases of the same character)
pub fn foldEqual(left: u21, right: u21) bool {
    return simpleCaseFold(left) == simpleCaseFold(right);
}

test "RuneRange.compare should compare Rune against an inclusive range" {
    try testing.expectEqual(
        LookupOrder.before,
        RuneRange.compare(10, 20, 9),
    );

    try testing.expectEqual(
        LookupOrder.match,
        RuneRange.compare(10, 20, 10),
    );

    try testing.expectEqual(
        LookupOrder.match,
        RuneRange.compare(10, 20, 15),
    );

    try testing.expectEqual(
        LookupOrder.match,
        RuneRange.compare(10, 20, 20),
    );

    try testing.expectEqual(
        LookupOrder.after,
        RuneRange.compare(10, 20, 21),
    );
}

test "unicode.ranges.isInClass should recognize Unicode numeric scalars" {
    try testing.expect(isInClass(.digit, '0'));
    try testing.expect(isInClass(.digit, '9'));

    try testing.expect(!isInClass(.digit, 'A'));
    try testing.expect(!isInClass(.digit, ' '));
}

test "unicode.ranges.isInClass should recognize Unicode alphabetical scalars" {
    try testing.expect(isInClass(.word, 'a'));
    try testing.expect(isInClass(.word, 'Z'));
    try testing.expect(isInClass(.word, '0'));

    try testing.expect(!isInClass(.word, ' '));
}

test "unicode.ranges.is should recognize Unicode whitespace scalars" {
    try testing.expect(isInClass(.whitespace, ' '));
    try testing.expect(isInClass(.whitespace, '\t'));
    try testing.expect(isInClass(.whitespace, '\n'));

    try testing.expect(!isInClass(.whitespace, 'a'));
}

test "unicode.ranges.simpleCaseFold should correctly fold character case" {
    try testing.expectEqual(
        @as(u21, 'a'),
        simpleCaseFold('A'),
    );

    try testing.expectEqual(
        @as(u21, 'z'),
        simpleCaseFold('Z'),
    );
}

test "unicode.ranges.simpleCaseFold should preserve character with no case mapping" {
    try testing.expectEqual(
        @as(u21, '1'),
        simpleCaseFold('1'),
    );
}

test "unicode.ranges.foldEqual should correctly compare characters with simple case folding" {
    try testing.expect(foldEqual('A', 'a'));
    try testing.expect(foldEqual('Z', 'z'));

    try testing.expect(!foldEqual('A', 'B'));
}
