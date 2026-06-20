const std = @import("std");
const regrex = @import("root.zig");
const Group = @import("./common/types.zig").Group;
const Match = regrex.Match;
const RegrexError = regrex.RegrexError;
const Pattern = regrex.Pattern;
const c_alloc = std.heap.c_allocator;

/// Cast C string to Zig slice
fn toSlice(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    if (len == 0) return "";

    const non_null = ptr orelse return null;
    return non_null[0..len];
}

// Error handling

/// C return codes
pub const regx_errcode_t = enum(c_uint) {
    REGREX_OK = 0,
    REGREX_EARG = 1,
    REGREX_ENOMATCH = 2,
    REGREX_ENOSPACE = 3,
    REGREX_EBADGRP = 4,
    REGREX_EBADUTF8 = 5,
    REGREX_ETOKEN = 6,
    REGREX_EEND = 7,
    REGREX_EEXPR = 8,
    REGREX_EBADESC = 9,
    REGREX_EBADREP = 10,
    REGREX_ERPAREN = 11,
    REGREX_ERBRACK = 12,
    REGREX_EINTERNAL = 255,
};

/// Converts Zig error set to C-compatible error code
fn toErrorCode(err: anyerror) regx_errcode_t {
    return switch(err) {
        RegrexError.NoMatch => .REGREX_ENOMATCH,
        RegrexError.MemoryError => .REGREX_ENOSPACE,
        RegrexError.InvalidGroupIndex => .REGREX_EBADGRP,
        RegrexError.InvalidUnicode => .REGREX_EBADUTF8,
        RegrexError.UnexpectedToken => .REGREX_ETOKEN,
        RegrexError.UnexpectedEnd => .REGREX_EEND,
        RegrexError.ExpressionExpected => .REGREX_EEXPR,
        RegrexError.TrailingEscape => .REGREX_EBADESC,
        RegrexError.InvalidRepeat => .REGREX_EBADREP,
        RegrexError.UnmatchedParen => .REGREX_ERPAREN,
        RegrexError.UnmatchedBracket => .REGREX_ERBRACK,
        else => .REGREX_EINTERNAL,
    };
}

/// Maps C return status codes to a string message
export fn regrex_error(code: regx_errcode_t) [*:0]const u8 {
    return switch (code) {
        .REGREX_OK => "OK",
        .REGREX_EARG => "Invalid argument",
        .REGREX_ENOMATCH => "No matching group",
        .REGREX_ENOSPACE => "Memory allocation error",
        .REGREX_EBADGRP => "Group index out of range",
        .REGREX_EBADUTF8 => "Invalid UTF-8 byte sequence",
        .REGREX_ETOKEN => "Invalid Token in current context",
        .REGREX_EEND => "Unexpected end of pattern",
        .REGREX_EEXPR => "Expression expected",
        .REGREX_EBADESC => "Trailing backslash at the pattern end",
        .REGREX_EBADREP => "Invalid use of repetition operator",
        .REGREX_ERPAREN => "Closing parenthesis missing",
        .REGREX_ERBRACK => "Closing bracket missing",
        .REGREX_EINTERNAL => "Internal Error",
    };
}

// Group
pub const regx_group_t = extern struct {
    start: usize,
    end: usize,
};

fn toExternGroup(group: Group) regx_group_t {
    return .{
        .start = group.start,
        .end = group.end,
    };
}

// Match
pub const regx_match_t = opaque {};

export fn regx_match_destroy(match: ?*regx_match_t) void {
    const m = match orelse return;

    const box: *MatchBox = @ptrCast(@alignCast(m));
    box.value.deinit(c_alloc);

    box.* = undefined;
    c_alloc.destroy(box);
}

export fn regx_match_groups_count(match: ?*const regx_match_t) c_int {
    const m = match orelse return 0;

    const box: *MatchBox = @ptrCast(@alignCast(m));

    return box.value.groups().len;
}

export fn regx_match_span(
    match: ?*const regx_match_t,
    i: usize,
    out_obj: ?*regx_group_t,
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;

    const box: *MatchBox = @ptrCast(@alignCast(m));

    const group = box.value.span(i) catch |err| {
        return toErrorCode(err);
    };

    out.* = toExternGroup(group);
    return .REGREX_OK;
}

const MatchBox = struct {
    value: Match,
};

fn initMatchHandle(match_val: Match) RegrexError!*regx_match_t {
    const box = c_alloc.create(MatchBox) catch {
        return RegrexError.MemoryError;
    };

    box.* = .{ .value = match_val };

    return @ptrCast(box);
}

fn storeMatch(result: ?Match, out_match: *?*regx_match_t) regx_errcode_t {
    out_match.* = null;

    var match_val = result orelse return .REGREX_ENOMATCH;

    const handle = initMatchHandle(match_val) catch |err| {
        match_val.deinit(c_alloc);
        return toErrorCode(err);
    };

    out_match.* = handle;
    return .REGREX_OK;
}

// []Match
pub const regx_match_list_t = opaque {};

export fn regx_match_list_destroy(list: ?*regx_match_list_t) void {
    const l = list orelse return;

    const box: *MatchListBox = @ptrCast(@alignCast(l));
    Match.free(c_alloc, box.matches);

    box.* = undefined;
    c_alloc.destroy(box);
}

export fn regx_match_list_len(list: ?*const regx_match_list_t) c_int {
    const l = list orelse return 0;
    const box: *MatchListBox = @ptrCast(@alignCast(l));

    return box.matches.len;
}

export fn regx_match_list_span(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    group_idx: usize,
    out_obj: ?*regx_group_t,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;

    const box: *MatchListBox = @ptrCast(@alignCast(l));

    if (match_idx >= box.matches.len) return .REGREX_EBADGRP;

    const group = box.matches[match_idx].span(group_idx) catch |err| {
        return toErrorCode(err);
    };

    out.* = toExternGroup(group);
    return .REGREX_OK;
}

const MatchListBox = struct {
    matches: []Match,
};

fn initMatchListHandle(matches: []Match) RegrexError!*regx_match_list_t {
    const box = c_alloc.create(MatchListBox) catch {
        return RegrexError.MemoryError;
    };

    box.* = .{ .matches = matches };

    return @ptrCast(box);
}

// Pattern
pub const regx_pattern_t = regrex.Pattern;

export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) void {
    const p = pattern orelse return;
    p.deinit();
}

// top-level one-off functions

export fn regrex_compile(
    pattern_str: ?[*]const u8,
    pattern_len: usize,
    out_obj: ?*?*regx_pattern_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toSlice(pattern_str, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const compiled = regrex.compile(c_alloc, pattern) catch |err| {
        return toErrorCode(err);
    };
    out.* = compiled;
    return .REGREX_OK;
}

const testing = std.testing;

test "extern.toErrorCode() maps Zig error set to corresponding return code" {
    try testing.expectEqual(
        .REGREX_EBADUTF8, 
        toErrorCode(RegrexError.InvalidUnicode),
    ); 
}

test "extern.regx_error() maps return code to corresponding string message" {
    const msg = "Invalid or malformed UTF-8 byte sequence";
    const slice = toSlice(regrex_error(.REGREX_EBADUTF8), msg.len) orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings(msg, slice);
}
