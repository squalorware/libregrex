const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;
const meta = @import("./meta.zig");
const T_Range = meta.T_Range;
const Sentinel = std.math.maxInt(usize);
const testing = std.testing;

pub const MAX_GROUPS_LEN = 1024;

pub const Span = T_Range(usize, .{ .extern_compat = true });

/// Sentinel offset to represent a capture group that took no part in matching
pub const EmptySpan = Span{ .start = Sentinel, .end = Sentinel };

pub fn isEmpty(span: Span) bool {
    return span.start == Sentinel and span.end == Sentinel;
}

pub const Match = struct {
    alloc: std.mem.Allocator,
    input: []const u8,
    /// Byte offsets of matches within the input.
    ///     `group[0]` always represents the full match.
    ///     `group[1..]` contains capture groups
    groups: []Span,

    pub fn init(
        allocator: std.mem.Allocator,
        captures_len: usize,
        input: []const u8,
        slots: []const ?usize,
    ) ErrorSet!Match {
        const full_start = slots[0] orelse 0;
        const full_end = slots[1] orelse full_start;
        const groups_len = captures_len + 1;

        if (groups_len > MAX_GROUPS_LEN) {
            return ErrorSet.GroupBufferOverflow;
        }
        var groups_buf = allocator.alloc(Span, groups_len) catch {
            return ErrorSet.MemoryError;
        };
        errdefer allocator.free(groups_buf);

        groups_buf[0] = .{
            .start = full_start,
            .end = full_end,
        };
        // Fill buffer with sentinel groups
        @memset(groups_buf[1..], EmptySpan);

        var subgroup_idx: usize = 1;
        while (subgroup_idx < groups_len) : (subgroup_idx += 1) {
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
            .alloc = allocator,
            .input = input,
            .groups = groups_buf,
        };
    }

    /// Releases the internal Span buffer and dereferences the Match
    pub fn deinit(self: *Match) void {
        const alloc = self.alloc;

        alloc.free(self.groups);
        self.* = undefined;
    }

    /// Locates and returns a byte offset at given index within the stored buffer
    pub fn span(self: Match, i: usize) ErrorSet!Span {
        if (i >= self.groups.len) return ErrorSet.OutOfRange;

        const g = self.groups[i];
        if (isEmpty(g)) return ErrorSet.NoMatch;

        return g;
    }

    /// Start offset of Span at index `i` within the buffer
    pub fn start(self: Match, i: usize) ErrorSet!usize {
        const g = try self.span(i);

        return g.start;
    }

    /// End offset of Span at index `i` within the buffer
    pub fn end(self: Match, i: usize) ErrorSet!usize {
        const g = try self.span(i);

        return g.end;
    }

    /// Returns a substring of input outlined by byte offset at index `i`
    pub fn group(self: Match, i: usize) ErrorSet![]const u8 {
        const g = try self.span(i);
        return self.input[g.start..g.end];
    }

    /// Returns a substring outlined by full match start and end
    pub fn full(self: Match) ErrorSet![]const u8 {
        return try self.group(0);
    }

    /// Returns capture groups (exceot full match)
    pub fn subgroups(self: Match) ErrorSet![]Span {
        return self.groups[1..];
    }
};

pub fn freeMatchCallback(alloc: std.mem.Allocator, ptr: *Match) void {
    _ = alloc;
    ptr.deinit();
}

/// A resizable dynamic buffer to store Match entries
pub const MatchListBuffer = meta.T_ManagedArrayList(Match, freeMatchCallback);

test "EmptySpan should return an empty Span" {
    const g = EmptySpan;

    try testing.expect(isEmpty(g));
}

test "isEmpty should return false for non-empty Span" {
    const g = Span{ .start = 1, .end = 3 };

    try testing.expect(!isEmpty(g));
}

const test_input = "lol 420 kek";

test "Match.init() should return a Match with valid full match and no capture groups" {
    const allocator = testing.allocator;
    // Capture slot with whole match start and end indices
    const slots = [_]?usize{ 4, 7 };

    var m = try Match.init(allocator, 0, test_input, slots[0..]);
    defer m.deinit();

    try testing.expectEqualStrings("420", try m.full());
    try testing.expectEqual(@as(usize, 4), try m.start(0));
    try testing.expectEqual(@as(usize, 7), try m.end(0));

    const subgroups = try m.subgroups();
    try testing.expectEqual(@as(usize, 0), subgroups.len);
}

test "Match.init() should return a Match with a valid subgroup" {
    const allocator = testing.allocator;
    const slots = [_]?usize{
        4,
        7,
        4,
        7,
    };

    var m = try Match.init(allocator, 1, test_input, slots[0..]);
    defer m.deinit();

    try testing.expectEqualStrings("420", try m.full());

    const subgroups = try m.subgroups();
    try testing.expectEqual(@as(usize, 1), subgroups.len);

    try testing.expectEqualStrings("420", try m.group(1));
    try testing.expectEqual(@as(usize, 4), try m.start(1));
    try testing.expectEqual(@as(usize, 7), try m.end(1));
}

test "Match.init() should create a Match with unmatched subgroups as sentinel groups" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, null, null };

    var m = try Match.init(allocator, 1, test_input, slots[0..]);
    defer m.deinit();

    try testing.expectEqualStrings("420", try m.full());

    const subgroups = try m.subgroups();
    const no_match_sent = subgroups[0];
    try testing.expect(isEmpty(no_match_sent));
}

test "Match.init() should create a Match with partially captured groups as sentinel groups" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, 4, null };

    var m = try Match.init(allocator, 1, test_input, slots[0..]);
    defer m.deinit();

    try testing.expectEqualStrings("420", try m.full());

    const subgroups = try m.subgroups();
    const no_match_sent = subgroups[0];
    try testing.expect(isEmpty(no_match_sent));
}

test "Match.init() should create a Match with multiple capture groups" {
    const allocator = testing.allocator;
    const slots = [_]?usize{
        0, 11, // group 0 (full match)
        0, 3, // group 1
        4, 7, // group 2
        8, 11, // group 3
    };
    const expected = [_][]const u8{ "lol", "420", "kek" };

    var m = try Match.init(allocator, 3, test_input, slots[0..]);
    defer m.deinit();

    try testing.expectEqualStrings("lol 420 kek", try m.full());

    const captures = try m.subgroups();

    try testing.expectEqual(@as(usize, 3), captures.len);

    for (captures, 0..) |_, i| {
        const group_idx = i + 1;
        try testing.expectEqualStrings(expected[i], try m.group(group_idx));
    }
}

test "Match.full() should return the full match string representation" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7 };
    const captures_len = slots.len / 2 - 1; // excluding full match

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    try testing.expectEqualStrings("420", try match.full());
}

test "Match.group(0) should return the full match string representation" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7 };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    try testing.expectEqualStrings("420", try match.full());
}

test "Match.span(0) should return the byte span of the full match" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7 };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    const result = try match.span(0);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i) should return a subgroup string representation" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, 4, 7 };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    const result = try match.group(1);

    try testing.expectEqualStrings("420", result);
}

test "Match.span(i) should return subgroup byte span" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, 4, 7 };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    const result = try match.span(1);

    try testing.expectEqual(@as(usize, 4), result.start);
    try testing.expectEqual(@as(usize, 7), result.end);
}

test "Match.group(i), Match.span(i) should return `Error.NoMatch` for an unmatched capture group" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, null, null };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    try testing.expectError(ErrorSet.NoMatch, match.group(1));
    try testing.expectError(ErrorSet.NoMatch, match.span(1));
}

test "Match.group(i), Match.span(i) should return `Error.OutOfRange` for a group out of range" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 4, 7, 4, 7 };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    try testing.expectError(ErrorSet.OutOfRange, match.group(2));
    try testing.expectError(ErrorSet.OutOfRange, match.span(2));
}

test "Match.subgroups() should return captures excluding full match" {
    const allocator = testing.allocator;
    const slots = [_]?usize{ 0, 7, 0, 3, 4, 7, null, null };
    const captures_len = slots.len / 2 - 1;

    var match = try Match.init(allocator, captures_len, test_input, slots[0..]);
    defer match.deinit();

    const result = try match.subgroups();

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqual(@as(usize, 0), result[0].start);
    try testing.expectEqual(@as(usize, 3), result[0].end);
    try testing.expectEqual(@as(usize, 4), result[1].start);
    try testing.expectEqual(@as(usize, 7), result[1].end);
    try testing.expect(isEmpty(result[2]));
}

test "MatchListBuffer.init() should create an empty array" {
    const allocator = testing.allocator;

    var matches = try MatchListBuffer.init(allocator, null);
    defer matches.deinit();

    try testing.expectEqual(@as(usize, 0), matches.len());
}

test "MatchListBuffer.append() should store owned matches" {
    const allocator = testing.allocator;

    var matches = try MatchListBuffer.init(allocator, null);
    defer matches.deinit();

    const slots = [_]?usize{ 4, 7 };
    const captures_len = slots.len / 2 - 1;

    const match = try Match.init(allocator, captures_len, test_input, slots[0..]);

    try matches.append(match);

    try testing.expectEqual(@as(usize, 1), matches.len());

    const stored = try matches.get(0);

    try testing.expectEqual(@as(usize, 4), stored.start(0));
    try testing.expectEqual(@as(usize, 7), stored.end(0));
}
