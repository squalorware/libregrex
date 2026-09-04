//! Various type casting/conversion utility functions
const std = @import("std");
const errors = @import("./error.zig");
const ext = @import("./ext.zig");
const matching = @import("./matching.zig");
const Flags = @import("./meta.zig").Flags;
const testing = std.testing;
const Match = matching.Match;
const Span = matching.Span;
const EmptySpan = matching.EmptySpan;
const isEmpty = matching.isEmpty;

/// Creates a `Match` instance from capture slots.
/// 
/// Allocates `subgroups` list on the heap to store the capture groups
/// and fills it with sentinel (`Group.none()`, no match) values, 
/// which are later replaced with actual capture groups from slots.
/// 
/// `captures_len` is a number of capture groups acquired during parsing.
/// 
/// Returns a `Match` instance with heap-allocated `subgroups` array on success:
/// - `subgroups[0]` contains the byte offset of a full match;
/// - `subgroups[1..]` contains the captured groups.
/// 
/// Returns `Error.MemoryError` if failed to allocate `subgroups` buffer
pub fn toMatch(
    allocator: std.mem.Allocator,
    input: []const u8,
    captures_len: usize,
    slots: []const ?usize,
) errors.ErrorSet!Match {
    const full_start = slots[0] orelse 0;
    const full_end = slots[1] orelse full_start;
    const groups_len = captures_len + 1;

    if (groups_len > matching.MAX_GROUPS_LEN) {
        return errors.ErrorSet.GroupBufferOverflow;
    }

    var groups_buf = allocator.alloc(Span, groups_len) catch {
        return errors.ErrorSet.MemoryError;
    };
    errdefer allocator.free(groups_buf);

    groups_buf[0] = .{
        .start = full_start,
        .end = full_end,
    };
    // Fill buffer with sentinel (no-match) groups
    @memset(groups_buf[1..], EmptySpan());

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
        .input = input,
        .groups = groups_buf,
    };
}

/// Converts a Unicode codepoint into a hexadecimal digit
pub fn toHexDigit(val: u21) ?u21 {
    return switch(val) {
        '0'...'9' => val - '0',
        'a'...'f' => val - 'a' + 10,
        'A'...'F' => val - 'A' + 10,
        else => null,
    };
}

/// Converts a Unicode codepoint into an octal digit
pub fn toOctDigit(val: u21) ?u21 {
    return switch(val) {
        '0'...'7' => val - '0',
        else => null,
    };
}

/// Converts Zig error set to C-compatible error code
pub fn toErrorCode(err: anyerror) ext.C_ReturnCode {
    return switch(err) {
        errors.ErrorSet.InvalidArgument => .REGREX_EARG,
        errors.ErrorSet.NoMatch => .REGREX_ENOMATCH,
        errors.ErrorSet.MemoryError => .REGREX_EMALLOC,
        errors.ErrorSet.OutOfRange => .REGREX_EBADGRP,
        errors.ErrorSet.GroupBufferOverflow => .REGREX_EMAXGRP,
        errors.ErrorSet.InvalidUnicode => .REGREX_EBADUTF8,
        errors.ErrorSet.UnexpectedToken => .REGREX_ETOKEN,
        errors.ErrorSet.UnexpectedEnd => .REGREX_EEND,
        errors.ErrorSet.ExpressionExpected => .REGREX_EEXPR,
        errors.ErrorSet.InvalidEscape,
        errors.ErrorSet.TrailingEscape => .REGREX_EBADESC,
        errors.ErrorSet.InvalidRepeat => .REGREX_EBADREP,
        errors.ErrorSet.UnmatchedParen => .REGREX_ERPAREN,
        errors.ErrorSet.UnmatchedBracket => .REGREX_ERBRACK,
        errors.ErrorSet.UnexpectedInstruction => .REGREX_EINSTERR,
        else => .ERR,
    };
}

/// Initializes a C-compatible buffer and copies all items from `sequence` (slice of `T`s).
///
/// Items are shallow-copied into the buffer.
pub fn initCBufferFromSlice(
    comptime T: type,
    alloc: std.mem.Allocator,
    buffer: *ext.C_GenericBuffer,
    destroy_cb: *const fn(*anyopaque) callconv(.c) void,
    sequence: []const T,
) ext.C_ReturnCode {
    const init_rc: ext.C_ReturnCode = ext.C_GenericBuffer.init(
        alloc,
        sequence.len,
        destroy_cb,
        @alignOf(T),
        @sizeOf(T),
        buffer,
    );
    if (init_rc != .OK) return init_rc;

    for (sequence) |item| {
        const push_rc = ext.C_GenericBuffer.push(buffer, &item);

        if (push_rc != .OK) {
            ext.C_GenericBuffer.deinit(alloc, buffer);
            return push_rc;
        }
    }
    return .OK;
}

pub fn bitmaskToFlags(mask: u8) Flags {
    return .{
        .ignore_case = mask & (1 << 0) != 0,
        .multiline = mask & (1 << 1) != 0,
        .dot_all = mask & (1 << 2) != 0,
    };
}

test "toMatch() should return a Match with valid full match and no capture groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7 };

    var m = try toMatch(allocator, input, 0, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", try m.full());
    try testing.expectEqual(@as(usize, 1), m.groups.len);
    try testing.expectEqual(@as(usize, 4), try m.start(0));
    try testing.expectEqual(@as(usize, 7), try m.end(0));

    try testing.expectEqual(@as(usize, 0), m.subgroups().len);
}

test "toMatch() should return a Match with a valid subgroup" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, 4, 7, };

    var m = try toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", try m.full());
    try testing.expectEqual(@as(usize, 2), m.groups.len);
    try testing.expectEqual(@as(usize, 1), m.subgroups().len);
    try testing.expectEqualStrings("420", try m.group(1));
    try testing.expectEqual(@as(usize, 4), try m.start(1));
    try testing.expectEqual(@as(usize, 7), try m.end(1));
}

test "toMatch() should create a Match with unmatched subgroups as sentinel groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, null, null };

    var m = try toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", try m.full());

    const no_match_sent = m.subgroups()[0];
    try testing.expect(isEmpty(no_match_sent));
}

test "toMatch() should create a Match with partially captured groups as sentinel groups" {
    const allocator = testing.allocator;
    const input = "lol 420 kek";
    // Capture slot with whole match start and end indices
    const slots = [_]?usize { 4, 7, 4, null };

    var m = try toMatch(allocator, input, 1, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("420", try m.full());

    const no_match_sent = m.subgroups()[0];
    try testing.expect(isEmpty(no_match_sent));
}

test "toMatch() should create a Match with multiple capture groups" {
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

    var m = try toMatch(allocator, input, 3, slots[0..]);
    defer m.deinit(allocator);

    try testing.expectEqualStrings("lol 420 kek", try m.full());
    try testing.expectEqual(@as(usize, 4), m.groups.len);

    const captures = m.subgroups();

    try testing.expectEqual(@as(usize, 3), captures.len);

    for (captures, 0..) |_, i| {
        const group_idx = i + 1;
        try testing.expectEqualStrings(expected[i], try m.group(group_idx));
    }
}
