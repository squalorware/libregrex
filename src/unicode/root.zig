const std = @import("std");
const Error = @import("types").Error;
const utypes = @import("./utypes.zig");
const table: utypes.RuneTable = @import("./rune_table.zon");
const testing = std.testing;
const RunePair = utypes.RunePair;
const CompareMode = utypes.CompareMode;
const SearchOrder = utypes.SearchOrder;
pub const CharRange = RunePair;
pub const CaseFold = RunePair;
pub const RuneClass = utypes.RuneClass;
pub const Rune = utypes.Rune;

/// Compares a Unicode codepoint against the lookup table
///
/// `mode` controls whether it is compared as a range or as a case-fold mapping
///
/// Returns the position of the scalar relative to the specified range
fn compare(map: RunePair, rune: u21, mode: CompareMode) SearchOrder {
    return switch(mode) {
        .range => RunePair.compare(map.start, map.end, rune),
        .case_fold => RunePair.compare(map.start, map.start, rune),
    };
}

/// Searches the scalar codepoint in the sorted lookup table
///
/// If `mode` is `CompareMode.range` the key is matched against
/// the inclusive `start..end` range of each item in `items`
///
/// If `mode` is `CompareMode.case_fold` uses only `item.start` as a lookup key
fn binarySearch(items: []const RunePair, key: u21, mode: CompareMode) ?*const RunePair {
    var low: usize = 0;
    var high: usize = items.len;

    while (low < high) {
        const mid = low + (high - low) / 2;

        switch (compare(items[mid], key, mode)) {
            .before => high = mid,
            .after => low = mid + 1,
            .match => return &items[mid],
        }
    }
    return null;
}

/// Checks if Rune occurs within given ranges
fn contains(ranges: []const CharRange, rune: u21) bool {
    return binarySearch(ranges, rune, CompareMode.range) != null;
}

/// Checks if Rune belongs to one of the preset character classes
pub fn is(cls: RuneClass, rune: u21) bool {
    return switch(cls) {
        .digit => contains(table.digit_ranges, rune),
        .word => contains(table.word_ranges, rune),
        .whitespace => contains(table.whitespace_ranges, rune),
    };
}

/// Searches for a simple Unicode case-fold mapping for `rune` in the lookup table
///
/// If `rune` has no correspondent mapping returns it unchanged
pub fn simpleCaseFold(rune: u21) u21 {
    const map = binarySearch(
        table.case_folds[0..],
        rune,
        CompareMode.case_fold
    ) orelse return rune;

    return map.end;
}

/// Checks the case-folding of two characters
/// (if mapping exists, given scalars are different cases of the same character)
pub fn foldEqual(left: u21, right: u21) bool {
    return simpleCaseFold(left) == simpleCaseFold(right);
}

test {
    _ = @import("./utypes.zig");
}

test "unicode.is should recognize Unicode numeric scalars" {
    try testing.expect(is(.digit, '0'));
    try testing.expect(is(.digit, '9'));

    try testing.expect(!is(.digit, 'A'));
    try testing.expect(!is(.digit, ' '));
}

test "unicode.is should recognize Unicode alphabetical scalars" {
    try testing.expect(is(.word, 'a'));
    try testing.expect(is(.word, 'Z'));
    try testing.expect(is(.word, '0'));

    try testing.expect(!is(.word, ' '));
}

test "unicode.is should recognize Unicode whitespace scalars" {
    try testing.expect(is(.whitespace, ' '));
    try testing.expect(is(.whitespace, '\t'));
    try testing.expect(is(.whitespace, '\n'));

    try testing.expect(!is(.whitespace, 'a'));
}

test "unicode.simpleCaseFold should correctly fold character case" {
    try testing.expectEqual(
        @as(u21, 'a'),
        simpleCaseFold('A'),
    );

    try testing.expectEqual(
        @as(u21, 'z'),
        simpleCaseFold('Z'),
    );
}

test "unicode.simpleCaseFold should preserve character with no case mapping" {
    try testing.expectEqual(
        @as(u21, '1'),
        simpleCaseFold('1'),
    );
}

test "unicode.foldEqual should correctly compare characters with simple case folding" {
    try testing.expect(foldEqual('A', 'a'));
    try testing.expect(foldEqual('Z', 'z'));

    try testing.expect(!foldEqual('A', 'B'));
}
