//! Match result representation for the regex engine.
//! 
//! Stores capture groups as substrings/byte spans of the input string.
//! 
//! Follows the conventional regex indexing model: 
//! group 0 represents the whole match;
//! groups 1..n represent the captured subgroups.
const std = @import("std");
const RegrexError = @import("./common/errors.zig").RegrexError;
const Group = @import("./common/types.zig").Group;

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
subgroups: []Group,

/// Releases allocator-owned capture group metadata.
/// 
/// Must be used with the same allocator that initialized `groups`
pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    alloc.free(self.subgroups);
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
/// `i = 0` returns the whole match.
/// 
/// Returns:
/// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
/// - `Error.NoMatch` if the group exists but did not participate in the match.
pub fn group(self: Self, i: usize) RegrexError![]const u8 {
    const g = try self.span(i);
    return self.input[g.start .. g.end];
}

/// Returns the byte span for a group.
/// 
/// `i = 0` returns the whole match span. 
/// 
/// Returns:
/// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
/// - `Error.NoMatch` if the group exists but did not participate in the match.
pub fn span(self: Self, i: usize) RegrexError!Group {
    if (i >= self.subgroups.len) return RegrexError.InvalidGroupIndex;

    const g = self.subgroups[i];
    if (g.isNone()) return RegrexError.NoMatch;

    return g;
}

/// Returns the whole matched text as a slice of `input`.
pub fn full(self: Self) []const u8 {
    const m = self.subgroups[0];
    return self.input[m.start .. m.end];
}

/// Returns the starting byte offset for capture group `i`
/// 
/// Returns:
/// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
/// - `Error.NoMatch` if the group exists but did not participate in the match.
pub fn start(self: Self, i: usize) RegrexError!usize {
    const g = try self.span(i);

    return g.start;
}

/// Returns the ending byte offset for capture group `i`
/// 
/// Returns:
/// - `Error.InvalidGroupIndex` if `i` is outside the available group range;
/// - `Error.NoMatch` if the group exists but did not participate in the match.
pub fn end(self: Self, i: usize) RegrexError!usize {
    const g = try self.span(i);

    return g.end;
}

/// Returns subgroups (capture groups excluding whole match at `group[0]`)
pub fn groups(self: Self) []const Group {
    return self.subgroups[1..];
}

/// Creates a `Match` instance from capture slots.
/// 
/// Allocates `subgroups` list on the heap to store the capture groups
/// and fills it with sentinel (`Group.none()`, no match) values, 
/// which are later replaced with actual capture groups from slots.
/// 
/// `captures_count` is a number of capture groups acquired during parsing.
/// 
/// Returns a `Match` instance with heap-allocated `subgroups` array on success:
/// - `subgroups[0]` contains the byte offset of a full match;
/// - `subgroups[1..]` contains the captured groups.
/// 
/// Returns `Error.MemoryError` if failed to allocate `subgroups` buffer
pub fn toMatch(
    allocator: std.mem.Allocator,
    input: []const u8,
    captures_count: usize,
    slots: []const ?usize,
) RegrexError!Self {
    const full_start = slots[0] orelse 0;
    const full_end = slots[1] orelse full_start;

    const group_count = captures_count + 1;

    var groups_buf = allocator.alloc(Group, group_count) catch {
        return RegrexError.MemoryError;
    };
    errdefer allocator.free(groups_buf);

    groups_buf[0] = .{
        .start = full_start,
        .end = full_end,
    };
    // Fill buffer with sentinel (no-match) groups
    @memset(groups_buf[1..], Group.none());

    var subgroup_idx: usize = 1;
    while (subgroup_idx < group_count) : (subgroup_idx += 1) {
        const start_slot = subgroup_idx * 2;
        const end_slot = start_slot + 1;

        const group_start = slots[start_slot] orelse continue;
        const group_end = slots[end_slot] orelse continue;

        groups_buf[subgroup_idx] = .{
            .start = group_start,
            .end = group_end,
        };
    }
    return .{
        .input = input,
        .subgroups = groups_buf,
    };
}

const testing = std.testing;
const test_input = "lol 420 kek";
/// Small test fixture that owns 
/// the allocated group metadata used by `Match`.
const TestContext = struct {
    match: Self,
    /// Creates a test match and copies group spans
    /// into allocator-owned memory.
    pub fn init(
        allocator: std.mem.Allocator,
        full_start: usize,
        full_end: usize,
        captures: []const Group,
    ) !TestContext {
        const owned_groups = try allocator.alloc(Group, captures.len + 1);
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
                .subgroups = owned_groups,
            },
        };
    }

    pub fn deinit(self: *TestContext, alloc: std.mem.Allocator) void {
        self.match.deinit(alloc);
        self.* = undefined;
    }
};

test "Match.full() should return the full match string representation" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    try testing.expectEqualStrings("420", ctx.match.full());
}

test "Match.group(0) should return the full match string representation" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    const result = try ctx.match.group(0);

    try testing.expectEqualStrings("420", result);
}

test "Match.span(0) should return the byte span of the full match" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator, 4, 7, &.{});
    defer ctx.deinit(allocator);

    const result = try ctx.match.span(0);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i) should return a subgroup string" {
    const allocator = testing.allocator;
    const captured = [_]Group {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    const result = try ctx.match.group(1);

    try testing.expectEqualStrings("420", result);
}

test "Match.span(i) should return subgroup byte span" {
    const allocator = testing.allocator;
    const captured = [_]Group {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    const result = try ctx.match.span(1);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i), Match.span(i) should return `Error.NoMatch` for an unmatched capture group" {
    const allocator = testing.allocator;
    const unmatched = [_]Group { 
        Group.none() 
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        test_input.len,
        unmatched[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectError(RegrexError.NoMatch, ctx.match.group(1));
    try testing.expectError(RegrexError.NoMatch, ctx.match.span(1)); 
}

test "Match.group(i), Match.span(i) should return `Error.InvalidGroupIndex` for a group out of range" {
    const allocator = testing.allocator;
    const captured = [_]Group {
        .{
            .start = 4,
            .end = 7,
        },
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        test_input.len,
        captured[0..],
    );
    defer ctx.deinit(allocator);

    try testing.expectError(RegrexError.InvalidGroupIndex, ctx.match.group(2));
    try testing.expectError(RegrexError.InvalidGroupIndex, ctx.match.span(2));
}

test "Match,groups() should return captures excluding full match" {
    const allocator = testing.allocator;
    const captures = [_]Group {
        .{ .start = 0, .end = 3 },
        .{ .start = 4, .end = 7 },
        Group.none(),
    };

    var ctx = try TestContext.init(
        allocator,
        0,
        test_input.len,
        captures[0..],
    );
    defer ctx.deinit(allocator);

    const result = ctx.match.groups();

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(usize, 0), result[0].start);
    try testing.expectEqual(@as(usize, 3), result[0].end);
    try testing.expectEqual(@as(usize, 4), result[1].start);
    try testing.expectEqual(@as(usize, 7), result[1].end);
    try testing.expect(result[2].isNone());
}

test "Match.toMatch(m) should return a Match with valid full match and no capture groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7 };

    var m = try toMatch(allocator, input, 0, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.full());
    try testing.expectEqual(@as(usize, 1), m.subgroups.len);
    try testing.expectEqual(@as(usize, 4), try m.start(0));
    try testing.expectEqual(@as(usize, 7), try m.end(0));

    try testing.expectEqual(@as(usize, 0), m.groups().len);
}

test "Match.toMatch(m) should return a Match with a valid subgroup" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, 4, 7, };

    var m = try toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.full());
    try testing.expectEqual(@as(usize, 2), m.subgroups.len);
    try testing.expectEqual(@as(usize, 1), m.groups().len);
    try testing.expectEqualStrings("420", try m.group(1));
    try testing.expectEqual(@as(usize, 4), try m.start(1));
    try testing.expectEqual(@as(usize, 7), try m.end(1));
}

test "Match.toMatch(m) should create a Match with unmatched subgroups as sentinel groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, null, null };

    var m = try Self.toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.full());

    const no_match_sent = m.groups()[0];
    try testing.expect(no_match_sent.isNone());
}

test "Match.toMatch(m) should create a Match with partially captured groups as sentinel groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, 4, null };

    var m = try Self.toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", m.full());

    const no_match_sent = m.groups()[0];
    try testing.expect(no_match_sent.isNone());
}

test "Match.toMatch(m) should create a Match with multiple capture groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize {
        0, 11, // group 0 (full match)
        0, 3, // group 1
        4, 7, // group 2
        8, 11 // group 3
    };
    const expected = [_][]const u8 {"lol", "420", "kek"};

    var m = try Self.toMatch(allocator, input, 3, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("lol 420 kek", m.full());
    try testing.expectEqual(@as(usize, 4), m.subgroups.len);

    const captures = m.groups();

    try testing.expectEqual(@as(usize, 3), captures.len);

    for (captures, 0..) |_, i| {
        const group_idx = i + 1;
        try testing.expectEqualStrings(expected[i], try m.group(group_idx));
    }
}
