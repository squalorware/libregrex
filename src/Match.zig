
//! Match result representation for the regex engine.
//! 
//! Stores byte spans into the original input buffer.
//! 
//! Follows the conventional regex indexing model: 
//! Group 0 represents the whole match;
//! it is not stored in `groups` but is derived from `span`.
//! Group 1..n represent the captured subgroups.
const std = @import("std");
const Error = @import("./common/errors.zig").Error;
const Span = @import("./common/types.zig").Span;

const MatchError = Error || std.mem.Allocator.Error;

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

/// Releases an allocator-owned slice of `Match` objects
/// 
/// Each `Match` owns its capture-group storage, so every item must be
/// deinitialized before the slice itself is freed.
pub fn free(alloc: std.mem.Allocator, matches: []Self) void {
    for (matches) |*m| {
        m.deinit(alloc);
    }

    alloc.free(matches);
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

/// Create a `Match` instance from capture slots.
/// 
/// Returns a `Match` which owns the allocated `groups` slice.
/// The caller is responsible for calling `Match.deinit()` on success
/// 
/// Returns `MatchError` if allocation error happened
pub fn toMatch(
    allocator: std.mem.Allocator,
    input: []const u8,
    group_count: usize,
    captures: []const ?usize,
) MatchError!Self {
    const start = captures[0] orelse 0;
    const end = captures[1] orelse start;

    var groups = try allocator.alloc(?Span, group_count);
    errdefer allocator.free(groups);

    var group_idx: usize = 0;
    while (group_idx < group_count) : (group_idx += 1) {
        const start_slot = (group_idx + 1) * 2;
        const end_slot = start_slot + 1;

        const group_start = captures[start_slot] orelse {
            groups[group_idx] = null;
            continue;
        };
        const group_end = captures[end_slot] orelse {
            groups[group_idx] = null;
            continue;
        };

        groups[group_idx] = .{
            .start = group_start,
            .end = group_end,
        };
    }
    return .{
        .input = input,
        .span = .{
            .start = start,
            .end = end,
        },
        .groups = groups,
    };
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

test "Should receive the whole match Span from capture slots passed to Match.toMatch" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const captures = [_]?usize { 4, 7 };

    var m = try Self.toMatch(allocator, input, 0, captures[0..]);
    defer m.deinit(allocator);

    try testing.expectEqual(@as(usize, 4), m.span.start);
    try testing.expectEqual(@as(usize, 7), m.span.end);
    try testing.expectEqualStrings("420", m.str());
    try testing.expectEqual(@as(usize, 0), m.groups.len);
}

test "Should create group spans from capture slots passed to Match.toMatch" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const captures = [_]?usize { 4, 7, 4, 7 };

    var m = try Self.toMatch(allocator, input, 1, captures[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.str());

    const group_str = m.group(1) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("420", group_str);

    const group_span = m.groupSpan(1) orelse {
        try testing.expect(false);
        return;
    };

    try testing.expectEqual(@as(usize, 4), group_span.start);
    try testing.expectEqual(@as(usize, 7), group_span.end);
}

test "Should set unmatched capture groups to null by Match.toMatch" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const captures = [_]?usize { 4, 7, null, null };

    var m = try Self.toMatch(allocator, input, 1, captures[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.str());
    try testing.expect(m.group(1) == null);
    try testing.expect(m.groupSpan(1) == null);
}

test "Should set partially captured group to null by Match.toMatch" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const captures = [_]?usize { 4, 7, 4, null };

    var m = try Self.toMatch(allocator, input, 1, captures[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.str());
    try testing.expect(m.group(1) == null);
    try testing.expect(m.groupSpan(1) == null);
}

test "Should create multiple capture groups by Match.toMatch" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const captures = [_]?usize {
        0, 11, // group 0
        0, 3, // group 1
        4, 7, // group 2
        8, 11 // group 3
    };
    const expected_groups = [_][]const u8 {"lol", "420", "kek"};

    var m = try Self.toMatch(allocator, input, 3, captures[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("lol 420 kek", m.str());

    for (expected_groups, 0..) |expected, i| {
        const group_idx = i + 1;
        const group_str = m.group(group_idx) orelse {
            try testing.expect(false);
            return;
        };
        try testing.expectEqualStrings(expected, group_str);
    }
}
