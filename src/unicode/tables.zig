const std = @import("std");
const types = @import("types");
const Error = types.Error;

const SearchOrder = enum {
    /// The key occurs before the current item
    before,
    /// The current item matches the key
    match,
    /// The key occurs after the current item
    after,
};

fn binarySearch(
    comptime T: type,
    items: []const T,
    key: u21,
    comptime compare: fn (T, u21) SearchOrder,
) ?*const T {
    var low: usize = 0;
    var high: usize = items.len;

    while (low < high) {
        const mid = low + (high - low) / 2;
        const item = items[mid];

        switch (compare(key, item)) {
            .before => high = mid,
            .after => low = mid + 1,
            .match => return &items[mid],
        }
    }
    return null;
}

pub const RangeType = enum {
    digit,
    word,
    whitespace,
};

const Range = struct {
    start: u21,
    end: u21,
    pub fn compare(mapping: Range, rune: u21) SearchOrder {
        if (rune < mapping.start) {
            return .before;
        }
        if (rune > mapping.end) {
            return .after;
        }
        return .match;
    }
};

const CaseFold = struct {
    source: u21,
    target: u21,
    pub fn compare(mapping: CaseFold, rune: u21) SearchOrder {
        if (rune < mapping.source) {
            return .before;
        }
        if (rune > mapping.source) {
            return .after;
        }
        return .match;
    }
};

const MappingTable = struct {
    // Unicode version
    version: []const u8,
    digit_ranges: []const Range,
    word_ranges: []const Range,
    whitespace_ranges: []const Range,
    case_folds: []const CaseFold,
};

pub const mapping_table: MappingTable = @import("./mapping_table.zon");

fn contains(ranges: []const Range, rune: u21) bool {
    return binarySearch(
        Range,
        ranges,
        rune,
        Range.compare,
    ) != null;
}

pub fn is(range_type: RangeType, rune: u21) Error!bool {
    return switch(range_type) {
        .digit => contains(mapping_table.digit_ranges, rune),
        .word => contains(mapping_table.word_ranges, rune),
        .whitespace => contains(mapping_table.whitespace_ranges, rune),
        else => return Error.InvalidUnicode,
    };
}

pub fn simpleCaseFold(rune: u21) u21 {
    const mapping = binarySearch(
        CaseFold,
        mapping_table.case_folds[0..],
        rune,
        CaseFold.compare,
    ) orelse return rune;

    return mapping.target;
}

pub fn equalFolded(left: u21, right: u21) bool {
    return simpleCaseFold(left) == simpleCaseFold(right);
}
