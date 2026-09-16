//! Integration tests on library as a whole
const std = @import("std");
const regrex = @import("regrex");
const testing = std.testing;

test "regrex.compile() should return a reusable *Pattern" {
    const allocator = testing.allocator;

    const pattern = try regrex.compile(allocator, "^[a-z]*$", .{});
    defer pattern.deinit();

    var result = try (pattern.match("abc")) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("abc", try result.full());

    const no_match = try pattern.match("abc1");
    try testing.expect(no_match == null);
}

test "regrex.match() should try to match only at the input start" {
    const allocator = testing.allocator;

    var result = (try regrex.match(
        allocator,
        "[0-9]+",
        "420 kek",
        .{},
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("420", try result.full());

    const no_match = try regrex.match(allocator, "[0-9]+", "lol 420 kek", .{});
    try testing.expect(no_match == null);
}

test "regrex.search() should return first match no matter its position in input" {
    const allocator = testing.allocator;

    var result = (try regrex.search(
        allocator,
        "[0-9]+",
        "lol 420 kek",
        .{},
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("420", try result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "regrex.search() should support Unicode literal matching" {
    const allocator = testing.allocator;

    var result = (try regrex.search(
        allocator,
        "う",
        "hうй",
        .{},
    )) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit();

    try testing.expectEqualStrings("う", try result.full());
}

test "regrex.findAll() should return all non-overlapping matches" {
    const allocator = testing.allocator;

    var matches = try regrex.findAll(
        allocator,
        "[0-9]+",
        "lol 420 kek 69",
        .{},
    );
    defer {
        for (matches) |m| {
            var owned = m;
            owned.deinit();
        }
        allocator.free(matches);
    }

    try testing.expectEqual(@as(usize, 2), matches.len);

    try testing.expectEqualStrings("420", try matches[0].full());
    try testing.expectEqual(@as(usize, 4), try matches[0].start(0));
    try testing.expectEqual(@as(usize, 7), try matches[0].end(0));

    try testing.expectEqualStrings("69", try matches[1].full());
    try testing.expectEqual(@as(usize, 12), try matches[1].start(0));
    try testing.expectEqual(@as(usize, 14), try matches[1].end(0));
}

test "regrex.sub() replaces all occurences matching pattern" {
    const allocator = testing.allocator;

    const result = try regrex.sub(allocator, "[0-9]+", "lol 420 kek 69", "SIXSEVEN", .{});
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek SIXSEVEN", result);
}

test "regrex.sub() acknowledges option.count and replaces exact number of occurences" {
    const allocator = testing.allocator;

    const result = try regrex.sub(
        allocator,
        "[0-9]+",
        "lol 67 kek 420",
        "SIXSEVEN",
        .{ .count = 1 },
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek 420", result);
}

test "regrex.sub() safely replaces all occurences if options.count is greater than actual matches count" {
    const allocator = testing.allocator;

    const result = try regrex.sub(
        allocator,
        "[0-9]+",
        "lol 67 kek 420",
        "SIXSEVEN",
        .{ .count = 67 },
    );
    defer allocator.free(result);

    try testing.expectEqualStrings("lol SIXSEVEN kek SIXSEVEN", result);
}
