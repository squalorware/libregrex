//! Shared primitive types used across Regrex engine.

const std = @import("std");
const maxInt = std.math.maxInt;

/// A Unicode scalar value.
/// 
/// Regrex performs matching at Unicode code point level
/// instead of native Zig UTF-8 byte slices.
/// 
/// Used to represent parsed literals, character class entries, 
/// decoded input characters etc.
pub const Rune = u21;

/// End-of-group sentinel value.
/// 
/// Uses a value outside of typical byte offset limit
pub const Sentinel = maxInt(usize);

/// A decoded UTF-8 code point and its original byte length.
/// 
/// Byte length is required because match spans are byte offsets
/// while matching itself is performed on decoded code points
pub const DecodedRune = struct {
    /// Unicode scalar value
    rune: Rune,
    /// Bytes consumed from original input
    len: usize,
};

/// Byte-indexed interval into an input string.
/// 
/// Follows Zig `slice` semantics
pub const Group = struct {
    /// Start offset, inclusive
    start: usize,
    /// End offset, exclusive
    end: usize,

    /// Returns a sentinel group representing no match.
    ///
    /// Used when a capture group did not participate in the match
    pub fn none() Group {
        return .{ 
            .start = Sentinel, 
            .end = Sentinel 
        };
    }

    /// Returns true if this group is a no-match sentinel
    pub fn isNone(self: Group) bool {
        return self.start == Sentinel and self.end == Sentinel;
    }
};

const testing = std.testing;

test "Group.none() should return a none (sentinel) group" {
    const g = Group.none();

    try testing.expect(g.isNone());
}

test "Group.isNone() should return false for matching Group" {
    const g = Group{ .start = 1, .end = 3 };

    try testing.expect(!g.isNone());
}
