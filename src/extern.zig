const std = @import("std");
const regrex = @import("root.zig");
const FindIterator = @import("./vm.zig").FindIterator;
const Group = @import("./common/types.zig").Group;
const cHelpers = @import("./common/chelpers.zig");

const storeBuffer = cHelpers.storeBuffer;
const WrappedOpaque = cHelpers.WrappedOpaque;
const Match = regrex.Match;
const RegrexError = regrex.RegrexError;
const Pattern = regrex.Pattern;
const c_alloc = std.heap.c_allocator;

//============================
// Exported C type definitions
//============================

/// Acceptable return codes
pub const regx_errcode_t = enum(c_uint) {
    REGREX_OK = 0,
    REGREX_EARG = 1,
    REGREX_ENOMATCH = 2,
    REGREX_ENOSPACE = 3,
    REGREX_EBADGRP = 4,
    REGREX_EMAXGRP = 5,
    REGREX_EBADUTF8 = 6,
    REGREX_ETOKEN = 7,
    REGREX_EEND = 8,
    REGREX_EEXPR = 9,
    REGREX_EBADESC = 10,
    REGREX_EBADREP = 11,
    REGREX_ERPAREN = 12,
    REGREX_ERBRACK = 13,
    REGREX_EINTERNAL = 255,
};
/// Group
pub const regx_group_t = extern struct {
    start: usize,
    end: usize,
};
/// Match
pub const regx_match_t = opaque {};
/// []Match
pub const regx_match_list_t = opaque {};
/// Pattern
pub const regx_pattern_t = regrex.Pattern;
/// FindIterator
pub const regx_iter_t = opaque {};

//=====================================
// Owned handlers for opaque types
//=====================================
fn freeMatchCallback(
    alloc: std.mem.Allocator,
    value: *Match,
) void {
    value.deinit(alloc);
}

fn freeMatchListCallback(
    alloc: std.mem.Allocator,
    value: *[]Match,
) void {
    Match.free(alloc, value.*);
}

const WrappedMatch = WrappedOpaque(regx_match_t, Match, freeMatchCallback);
const WrappedMatchList = WrappedOpaque(regx_match_list_t, []Match, freeMatchListCallback);
const WrappedIterator = struct {
    value: FindIterator,

    pub fn unwrap(ptr: *regx_iter_t) *FindIterator {
        return @ptrCast(@alignCast(ptr));
    }
};

fn storeMatch(match: ?Match, out_obj: *?*regx_match_t) RegrexError!void {
    out_obj.* = null;

    var m = match orelse return RegrexError.NoMatch;

    const handle = WrappedMatch.create(c_alloc, m) catch |err| {
        m.deinit(c_alloc);
        return err;
    };

    out_obj.* = handle;
}

//==================================
// C-compatible API implementation
//==================================

export fn regx_match_destroy(match: ?*regx_match_t) void {
    WrappedMatch.destroy(c_alloc, match);
}

export fn regx_match_groups_len(match: ?*const regx_match_t, out_i: ?*usize) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_i orelse return .REGREX_EARG;
    const owned = WrappedMatch.unwrapConst(m);

    out.* = owned.value.groups().len;
    return .REGREX_OK;
}

export fn regx_match_span(
    match: ?*const regx_match_t,
    i: usize,
    out_obj: ?*regx_group_t,
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const owned = WrappedMatch.unwrapConst(m);

    const result = owned.value.span(i) catch |err| {
        return toErrorCode(err);
    };

    out.* = toExternGroup(result);
    return .REGREX_OK;
}

export fn regx_match_group(
    match: ?*const regx_match_t,
    i: usize,
    out_ptr: ?*?[*:0]const u8,
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_ptr orelse return .REGREX_EARG;
    const owned = WrappedMatch.unwrapConst(m);

    const result = owned.value.group(i) catch |err| {
        return toErrorCode(err);
    };
    out.* = toCString(c_alloc, result) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

export fn regx_match_list_destroy(list: ?*regx_match_list_t) void {
    WrappedMatchList.destroy(c_alloc, list);
}

export fn regx_match_list_len(list: ?*const regx_match_list_t, out_i: ?*usize) regx_errcode_t {
    const l = list orelse return 0;
    const out = out_i orelse return .REGREX_EARG;
    const owned = WrappedMatchList.unwrapConst(l);

    out.* = owned.value.len;
    return .REGREX_OK;
}

export fn regx_match_list_span(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    group_idx: usize,
    out_obj: ?*regx_group_t,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const owned = WrappedMatchList.unwrapConst(l);

    if (match_idx >= owned.matches.len) return .REGREX_EBADGRP;

    const result = owned.matches[match_idx].span(group_idx) catch |err| {
        return toErrorCode(err);
    };

    out.* = toExternGroup(result);
    return .REGREX_OK;
}

export fn regx_match_list_group(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    group_idx: usize,
    out_ptr: ?*?[*:0]const u8,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_ptr orelse return .REGREX_EARG;
    const owned = WrappedMatchList.unwrapConst(l);

    if (match_idx >= owned.value.len) return .REGREX_EBADGRP;

    const result = owned.value[match_idx].group(group_idx) catch |err| {
        return toErrorCode(err);
    };

    out.* = toCString(c_alloc, result) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) void {
    const p = pattern orelse return;
    p.deinit();
}

export fn regx_pattern_search(
    pattern: ?*const regx_pattern_t,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    out.* = null;
    const match = p.search(input) catch |err| {
        return toErrorCode(err);
    };
    storeMatch(match, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

export fn regx_pattern_match(
    pattern: ?*const regx_pattern_t,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    const match = p.match(input) catch |err| {
        out.* = null;
        return toErrorCode(err);
    };
    storeMatch(match, out) catch |err| {
        out.* = null;
        return toErrorCode(err);
    };
}

export fn regx_pattern_find_iter(
    pattern: ?*const regx_pattern_t,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_iter_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    out.* = null;

    const owned = c_alloc.create(WrappedIterator) catch {
        return .REGREX_ENOSPACE;
    };
    errdefer c_alloc.destroy(owned);

    owned.* = .{ .value = p.findIter(input) };
    return .REGREX_OK;
}

export fn regx_pattern_find_all(
    pattern: ?*const regx_pattern_t,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_list_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    out.* = null;

    const matches = p.findAll(input) catch |err| {
        return toErrorCode(err);
    };
    const result = WrappedMatchList.create(c_alloc, matches) catch |err| {
        return toErrorCode(err);
    };

    out.* = result;
    return .REGREX_OK;
}

export fn regx_pattern_sub(
    pattern: ?*const regx_pattern_t,
    repl_ptr: ?[*]const u8,
    repl_len: usize,
    input_ptr: ?[*]const u8,
    input_len: usize,
    count: ?c_uint,
    out_ptr: ?*?[*] u8,
    out_len: ?*usize,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const outp = out_ptr orelse return .REGREX_EARG;
    const outl = out_len orelse return .REGREX_EARG;
    const repl = toOwnedSlice(repl_ptr, repl_len) orelse {
        return .REGREX_EARG;
    };
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };
    const c = count orelse 0;

    const buf = p.sub(repl, input, .{ .count = @as(usize, c) }) catch |err| {
        return toErrorCode(err);
    };
    storeBuffer(c_alloc, buf, outp, outl);
    return .REGREX_OK;
}

export fn regx_iter_next(
    iter: ?*regx_iter_t,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const i = iter orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const owned = WrappedIterator.unwrap(i);

    const match = (owned.value.next() catch |err| {
        return toErrorCode(err);
    }) orelse return .REGREX_ENOMATCH;

    storeMatch(match, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

export fn regrex_str_destroy(ptr: ?[*:0]const u8) void {
    const p = ptr orelse return;

    const mut: [*:0]u8 = @constCast(p);
    c_alloc.free(mut[0 .. std.mem.len(p) + 1]);
}

/// Maps C return status codes to a string message
export fn regrex_error(code: regx_errcode_t) [*:0]const u8 {
    return switch (code) {
        .REGREX_OK => "OK",
        .REGREX_EARG => "Invalid argument",
        .REGREX_ENOMATCH => "No matching group",
        .REGREX_ENOSPACE => "Memory allocation error",
        .REGREX_EBADGRP => "Group index out of range",
        .REGREX_EMAXGRP => "Exceeded maximum group count limit",
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

/// Compiles the pattern
export fn regrex_compile(
    pattern_ptr: ?[*]const u8,
    pattern_len: usize,
    out_obj: ?*?*regx_pattern_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_ptr, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const compiled = regrex.compile(c_alloc, pattern) catch |err| {
        return toErrorCode(err);
    };
    out.* = compiled;
    return .REGREX_OK;
}

export fn regrex_search(
    pattern_ptr: ?[*]const u8,
    pattern_len: usize,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_ptr, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    const result = regrex.search(c_alloc, pattern, input) catch |err| {
        return toErrorCode(err);
    };

    return storeMatch(result, out);
}

export fn regrex_match(
    pattern_ptr: ?[*]const u8,
    pattern_len: usize,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_ptr, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    const result = regrex.match(c_alloc, pattern, input) catch |err| {
        return toErrorCode(err);
    };

    return storeMatch(result, out);
}

export fn regrex_find_all(
    pattern_ptr: ?[*]const u8,
    pattern_len: usize,
    input_ptr: ?[*]const u8,
    input_len: usize,
    out_obj: ?*?*regx_match_list_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_ptr, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    const result = regrex.findAll(c_alloc, pattern, input) catch |err| {
        return toErrorCode(err);
    };

    const wrapped = WrappedMatchList.create(c_alloc, result) catch |err| {
        return toErrorCode(err);
    };

    out.* = wrapped;
    return .REGREX_OK;
}

export fn regrex_sub(
    pattern_ptr: ?[*]const u8,
    pattern_len: usize,
    repl_ptr: ?[*]const u8,
    repl_len: usize,
    input_ptr: ?[*]const u8,
    input_len: usize,
    count: ?usize,
    out_ptr: ?*?[*]u8,
    out_len: ?*usize,
) regx_errcode_t {
    const c = count orelse 0;

    const outp = out_ptr orelse return .REGREX_EARG;
    const outl = out_len orelse return .REGREX_EARG;

    outp.* = null;
    outl.* = 0;

    const pattern = toOwnedSlice(pattern_ptr, pattern_len) orelse {
        return .REGREX_EARG;
    };
    const repl = toOwnedSlice(repl_ptr, repl_len) orelse {
        return .REGREX_EARG;
    };
    const input = toOwnedSlice(input_ptr, input_len) orelse {
        return .REGREX_EARG;
    };

    const buffer = regrex.sub(
        c_alloc, 
        pattern, 
        repl,
        input,
        .{ .count = c }
        ) catch |err| {
        return toErrorCode(err);
    };

    storeBuffer(c_alloc, buffer, outp, outl);
    return .REGREX_OK;
}

//====================================
// Type conversions between Zig and C
//====================================
const toOwnedSlice = cHelpers.toOwnedSlice;

const toCString = cHelpers.toCString;

/// Converts Zig error set to C-compatible error code
fn toErrorCode(err: anyerror) regx_errcode_t {
    return switch(err) {
        RegrexError.InvalidArgument => .REGREX_EARG,
        RegrexError.NoMatch => .REGREX_ENOMATCH,
        RegrexError.MemoryError => .REGREX_ENOSPACE,
        RegrexError.InvalidGroupIndex => .REGREX_EBADGRP,
        RegrexError.GroupBufferOverflow => .REGREX_EMAXGRP,
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
/// Converts Zig Group structure to C representation
fn toExternGroup(group: Group) regx_group_t {
    return .{
        .start = group.start,
        .end = group.end,
    };
}

const testing = std.testing;

test "toErrorCode() maps Zig error set to corresponding return code" {
    try testing.expectEqual(
        .REGREX_EBADUTF8, 
        toErrorCode(RegrexError.InvalidUnicode),
    ); 
}

test "regrex_error() maps return code to corresponding string message" {
    const msg = "Invalid or malformed UTF-8 byte sequence";
    const slice = toOwnedSlice(regrex_error(.REGREX_EBADUTF8), msg.len) orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings(msg, slice);
}
