const std = @import("std");
const Error = @import("types").Error;
const utypes = @import("./utypes.zig");
const table: utypes.RuneTable = @import("./rune_table.zon");
const RunePair = utypes.RunePair;
const CompareMode = utypes.CompareMode;
const SearchOrder = utypes.SearchOrder;
pub const CharRange = RunePair;
pub const CaseFold = RunePair;
pub const RuneClass = utypes.RuneClass;
pub const Rune = utypes.Rune;

fn compare(map: RunePair, rune: u21, mode: CompareMode) SearchOrder {
    return switch(mode) {
        .range => RunePair.compare(map.start, map.end, rune),
        .case_fold => RunePair.compare(map.start, map.start, rune),
    };
}

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

fn contains(ranges: []const CharRange, rune: u21) bool {
    return binarySearch(ranges, rune, CompareMode.range) != null;
}

pub fn is(cls: RuneClass, rune: u21) bool {
    return switch(cls) {
        .digit => contains(table.digit_ranges, rune),
        .word => contains(table.word_ranges, rune),
        .whitespace => contains(table.whitespace_ranges, rune),
    };
}

pub fn simpleCaseFold(rune: u21) u21 {
    const map = binarySearch(
        table.case_folds[0..],
        rune,
        CompareMode.case_fold
    ) orelse return rune;

    return map.end;
}

pub fn foldEqual(left: u21, right: u21) bool {
    return simpleCaseFold(left) == simpleCaseFold(right);
}
