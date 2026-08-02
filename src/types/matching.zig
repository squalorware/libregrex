const std = @import("std");
const Error = @import("./error.zig").Error;
pub const ManagedArrayList = @import("./managed.zig").ManagedArrayList;
const Sentinel = std.math.maxInt(usize);

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
    /// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn span(self: Match, i: usize) Error!Span {
        if (i >= self.groups.len) return Error.InvalidGroupIndex;

        const g = self.groups[i];
        if (g.isNone()) return Error.NoMatch;

        return g;
    }

    /// Returns the starting index of byte span `i`
    ///
    /// Returns:
    /// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
    /// - `Error.NoMatch` if the group exists but did not participate in the match.
    pub fn start(self: Match, i: usize) Error!usize {
        const g = try self.span(i);

        return g.start;
    }

    /// Returns the ending index of byte span `i`
    ///
    /// Returns:
    /// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
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
    /// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
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

pub const MatchList = ManagedArrayList(Match, null);
    // const testing = std.testing;

    // test "Span.none() should return an empty Span" {
    //     const g = Span.none();

    //     try testing.expect(g.isNone());
    // }

    // test "Span.isNone() should return false for non-empty Span" {
    //     const g = Span{ .start = 1, .end = 3 };

    //     try testing.expect(!g.isNone());
    // }