const std = @import("std");
const Error = @import("./error.zig").Error;
const ManagedDynamicBuffer = @import("./managed.zig").ManagedDynamicBuffer;
const Sentinel = std.math.maxInt(usize);
const testing = std.testing;

pub const MAX_GROUPS_LEN = 1024;

/// Holds starting and ending indices of a byte range inside a string
///
/// Follows slice semantics - `start` is inclusive, `end` is exclusive
pub const Span = struct {
    start: usize,
    end: usize,

    /// Creates a span where start and end are set to sentinel values
    ///
    /// Used when a capture group did not participate in the match.
    ///
    /// Sentinel values are explicitly out of range for any possible string
    pub fn none() Span {
        return .{
            .start = Sentinel,
            .end = Sentinel,
        };
    }

    /// Checks if this span is empty (represents no match)
    pub fn isNone(self: Span) bool {
        return self.start == Sentinel and self.end == Sentinel;
    }
};
    
test "Span.none() should return an empty Span" {
    const g = Span.none();

    try testing.expect(g.isNone());
}

test "Span.isNone() should return false for non-empty Span" {
    const g = Span{ .start = 1, .end = 3 };

    try testing.expect(!g.isNone());
}

pub const Match = struct {
    /// Borrowed input buffer against which the regex was executed.
    ///
    /// All returned slices from `Match.full()`
    /// and `Match.group(i)` point into this buffer.
    input: []const u8,
    /// Capture groups
    ///
    /// `groups[0]` corresponds to full match
    ///
    /// If member Group is a sentinel (`Group.isNone(group) == true`)
    /// it means that group exists but took no part in matching
    groups: []Span,

    /// Releases allocator-owned capture group metadata.
    ///
    /// Must be used with the same allocator that initialized `groups`
    pub fn deinit(self: *Match, alloc: std.mem.Allocator) void {
        alloc.free(self.groups);
        self.* = undefined;
    }

    /// Returns the byte Span at given index.
    ///
    /// `i = 0` returns the whole match span.
    ///
    /// Returns:
    /// - `Error.OutOfRange` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn span(self: Match, i: usize) Error!Span {
        if (i >= self.groups.len) return Error.OutOfRange;

        const g = self.groups[i];
        if (g.isNone()) return Error.NoMatch;

        return g;
    }

    /// Returns the starting index of byte span `i`
    ///
    /// Returns:
    /// - `Error.OutOfRange` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn start(self: Match, i: usize) Error!usize {
        const g = try self.span(i);

        return g.start;
    }

    /// Returns the ending index of byte span `i`
    ///
    /// Returns:
    /// - `Error.OutOfRange` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn end(self: Match, i: usize) Error!usize {
        const g = try self.span(i);

        return g.end;
    }

    /// Returns slice of `input` from `Span.start` to `Span.end`.
    ///
    /// `i = 0` returns the whole match.
    ///
    /// Returns:
    /// - `Error.OutOfRange` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn group(self: Match, i: usize) Error![]const u8 {
        const g = try self.span(i);
        return self.input[g.start..g.end];
    }

    /// Returns slice of `input` which corresponds to full match
    pub fn full(self: Match) Error![]const u8 {
        return try self.group(0);
    }

    /// Returns Spans except `group[0]` which contain capture groups
    pub fn subgroups(self: Match) []const Span {
        return self.groups[1..];
    }
};

const test_input = "lol 420 kek";

const MatchFixture = struct {
    match: Match,
    /// Creates a test match and copies group spans
    /// into allocator-owned memory.
    pub fn init(
        allocator: std.mem.Allocator,
        full_start: usize,
        full_end: usize,
        captures: []const Span,
    ) !MatchFixture {
        const owned_groups = try allocator.alloc(Span, captures.len + 1);
        owned_groups[0] = .{
            .start = full_start,
            .end = full_end,
        };
        for (captures, 0..) |g, i| {
            owned_groups[i + 1] = g;
        }

        return .{
            .match = .{
                .input = test_input,
                .groups = owned_groups,
            },
        };
    }

    pub fn deinit(self: *MatchFixture, alloc: std.mem.Allocator) void {
        self.match.deinit(alloc);
        self.* = undefined;
    }
};

test "Match.full() should return the full match string representation" {
    const allocator = testing.allocator;
    var fix = try MatchFixture.init(allocator, 4, 7, &.{});
    defer fix.deinit(allocator);

    try testing.expectEqualStrings("420", try fix.match.full());
}

test "Match.group(0) should return the full match string representation" {
    const allocator = testing.allocator;
    var fix = try MatchFixture.init(allocator, 4, 7, &.{});
    defer fix.deinit(allocator);

    const result = try fix.match.group(0);

    try testing.expectEqualStrings("420", result);
}

test "Match.span(0) should return the byte span of the full match" {
    const allocator = testing.allocator;
    var fix = try MatchFixture.init(allocator, 4, 7, &.{});
    defer fix.deinit(allocator);

    const result = try fix.match.span(0);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i) should return a subgroup string representation" {
    const allocator = testing.allocator;
    const captured = [_]Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var fix = try MatchFixture.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer fix.deinit(allocator);

    const result = try fix.match.group(1);

    try testing.expectEqualStrings("420", result);
}

test "Match.span(i) should return subgroup byte span" {
    const allocator = testing.allocator;
    const captured = [_]Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var fix = try MatchFixture.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer fix.deinit(allocator);

    const result = try fix.match.span(1);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i), Match.span(i) should return `Error.NoMatch` for an unmatched capture group" {
    const allocator = testing.allocator;
    const unmatched = [_]Span { 
        Span.none() 
    };

    var fix = try MatchFixture.init(
        allocator,
        0,
        test_input.len,
        unmatched[0..],
    );
    defer fix.deinit(allocator);

    try testing.expectError(Error.NoMatch, fix.match.group(1));
    try testing.expectError(Error.NoMatch, fix.match.span(1)); 
}

test "Match.group(i), Match.span(i) should return `Error.OutOfRange` for a group out of range" {
    const allocator = testing.allocator;
    const captured = [_]Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var fix = try MatchFixture.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer fix.deinit(allocator);

    try testing.expectError(Error.OutOfRange, fix.match.group(2));
    try testing.expectError(Error.OutOfRange, fix.match.span(2));
}

test "Match.subgroups() should return captures excluding full match" {
    const allocator = testing.allocator;
    const captures = [_]Span {
        .{ .start = 0, .end = 3 },
        .{ .start = 4, .end = 7 },
        Span.none(),
    };

    var fix = try MatchFixture.init(
        allocator,
        0,
        test_input.len,
        captures[0..],
    );
    defer fix.deinit(allocator);

    const result = fix.match.subgroups();

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(usize, 0), result[0].start);
    try testing.expectEqual(@as(usize, 3), result[0].end);
    try testing.expectEqual(@as(usize, 4), result[1].start);
    try testing.expectEqual(@as(usize, 7), result[1].end);
    try testing.expect(result[2].isNone());
}

/// A resizable dynamic buffer to store Match entries
pub const MatchListBuffer = ManagedDynamicBuffer(Match, null);

test "MatchArray.init() should create an empty array" {
    const allocator = testing.allocator;

    var matches = try MatchListBuffer.init(allocator, null);
    defer matches.deinit();

    try testing.expectEqual(@as(usize, 0), matches.len());
}

test "MatchArray.append() should store owned matches" {
    const allocator = testing.allocator;

    var matches = try MatchListBuffer.init(allocator, null);
    defer matches.deinit();

    const groups = try allocator.alloc(Span, 1);
    groups[0] = .{
        .start = 0,
        .end = 3,
    };

    const m = Match{
        .input = "kek",
        .groups = groups,
    };

    try matches.append(m);

    try testing.expectEqual(@as(usize, 1), matches.len());

    const stored = try matches.get(0);

    try testing.expectEqualStrings("kek", stored.input);
    try testing.expectEqual(@as(usize, 1), stored.groups.len);
    try testing.expectEqual(@as(usize, 0), stored.groups[0].start);
    try testing.expectEqual(@as(usize, 3), stored.groups[0].end);
}

