
//! Match result representation for the regex engine.
//! 
//! Stores byte spans into the original input buffer.
//! 
//! Follows the conventional regex indexing model: 
//! Group 0 represents the whole match;
//! it is not stored in `groups` but is derived from `span`.
//! Group 1..n represent the captured subgroups.
const std = @import("std");
const Span = @import("./common/types.zig").Span;

pub const Self = @This();

/// Borrowed input buffer against which the regex was executed.
///
/// All returned slices from `str` and `group` point into this buffer.
input: []const u8,
/// Byte span of the whole match within `input`
span: Span,
/// Optional byte spans for capturing groups (subgroups).
/// 
/// `groups[0]` corresponds to regex group (subgroup) 1,
/// `groups[1]` corresponds to regex group (subgroup) 2,
/// and so on. `null` means that group exists but took
/// no part in match.
groups: []?Span,

/// Releases allocator-owned capture group metadata.
/// 
/// Must be used with the same allocator that initialized `groups`
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    alloc.free(self.groups);
    self.* = undefined;
}

/// Returns the text matched by a group.
/// 
/// `idx = 0` returns the whole match. `idx > 0` is interpreted
/// as a capturing group index. 
/// 
/// Returns `null` if requested group is out of range or
/// did not take part in match. 
pub fn group(self: Self, idx: usize) ?[]const u8 {
    if (idx == 0) {
        return self.str();
    }

    const span = self.groupSpan(idx) orelse return null;

    return self.input[span.start..span.end];
}
/// Returns the byte span for a group.
/// 
/// `idx = 0` returns the whole match span. 
/// `idx > 0` is interpreted as a capturing group span index. 
/// 
/// Returns `null` if requested group span is out of range or
/// did not take part in match. 
pub fn groupSpan(self: Self, idx: usize) ?Span {
    if (idx == 0) {
        return self.span;
    }

    const group_idx = idx - 1;

    if (group_idx >= self.groups.len) {
        return null;
    }

    return self.groups[group_idx];
}
/// Returns the whole matched text as a slice of `input`.
pub fn str(self: Self) []const u8 {
    return self.input[self.span.start..self.span.end];
}

const testing = std.testing;
const testInput = "lol 420 kek";
/// Small test fixture that owns 
/// the allocated group metadata used by `Match`.
const TestContext = struct {
    match: Self,
    /// Creates a test match and copies group spans
    /// into allocator-owned memory.
    pub fn init(
        alloc: std.mem.Allocator,
        start: usize,
        end: usize,
        groups: []const ?Span,
    ) !TestContext {
        const owned_groups = try alloc.dupe(?Span, groups);

        return .{
            .match = .{
                .input = testInput,
                .span = .{
                    .start = start,
                    .end = end,
                },
                .groups = owned_groups,
            },
        };
    }

    pub fn deinit(self: *TestContext, alloc: std.mem.Allocator) void {
        self.match.deinit(alloc);
        self.* = undefined;
    }
};

test "Should receive the whole match slice from Match.str" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    try testing.expectEqualStrings("420", ctx.match.str());
}

test "Should receive the whole match slice from Match.group 0" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    const maybe_grp: ?[]const u8 = ctx.match.group(0);

    if (maybe_grp) |grp| {
        try testing.expectEqualStrings("420", grp);
    } else {
        try testing.expect(false);
    }
}

test "Should receive the whole match Span from Match.groupSpan 0" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    const maybe_span: ?Span = ctx.match.groupSpan(0);

    if (maybe_span) |span| {
        try testing.expectEqual(@as(usize, 4), span.start);
        try testing.expectEqual(@as(usize, 7), span.end);
    } else {
        try testing.expect(false);
    }
}

test "Should receive captured group slice from Match.group" {
    const allocator = testing.allocator;
    const captured = [_]?Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    const maybe_grp: ?[]const u8 = ctx.match.group(1);
    if (maybe_grp) |grp| {
        try testing.expectEqualStrings("420", grp);
    } else {
        try testing.expect(false);
    }
}

test "Should receive captured group span from Match.groupSpan" {
    const allocator = testing.allocator;
    const captured = [_]?Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    const maybe_span: ?Span = ctx.match.groupSpan(1);
    if (maybe_span) |span| {
        try testing.expectEqual(@as(usize, 4), span.start);
        try testing.expectEqual(@as(usize, 7), span.end);
    } else {
        try testing.expect(false);
    }
}

test "Should receive null from Match.group for unmatched capture group" {
    const allocator = testing.allocator;
    const unmatched = [_]?Span { null };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        unmatched[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectEqual(@as(?[]const u8, null), ctx.match.group(1)); 
}

test "Should receive null from Match.groupSpan for unmatched capture group" {
    const allocator = testing.allocator;
    const unmatched = [_]?Span { null };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        unmatched[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectEqual(@as(?Span, null), ctx.match.groupSpan(1)); 
}

test "Should receive null from Match.group for group out of range" {
    const allocator = testing.allocator;
    const captured = [_]?Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectEqual(@as(?[]const u8, null), ctx.match.group(2));
}

test "Should receive null from Match.groupSpan for group out of range" {
    const allocator = testing.allocator;
    const captured = [_]?Span {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        testInput.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectEqual(@as(?Span, null), ctx.match.groupSpan(2));
}

