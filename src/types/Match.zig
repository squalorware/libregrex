const std = @import("std");
const Error = @import("./error.zig").Error;
const Span = @import("./Span.zig");

pub const Self = @This();

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
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
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
pub fn span(self: Self, i: usize) Error!Span {
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
pub fn start(self: Self, i: usize) Error!usize {
    const g = try self.span(i);

    return g.start;
}

/// Returns the ending index of byte span `i`
///
/// Returns:
/// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
/// - `Error.NoMatch` if the group exists but did not participate in the match.
pub fn end(self: Self, i: usize) Error!usize {
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
pub fn group(self: Self, i: usize) Error![]const u8 {
    const g = try self.span(i);
    return self.input[g.start..g.end];
}

/// Returns slice of `input` which corresponds to full match
pub fn full(self: Self) Error![]const u8 {
    return try self.group(0);
}

/// Returns Spans except `group[0]` which contain capture groups
pub fn subgroups(self: Self) []const Span {
    return self.groups[1..];
}
