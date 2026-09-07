const std = @import("std");
const regrex = @import("regrex");
const types = @import("types");
const conv = types.conv;
const ext = types.ext;
const hasDeinit = types.meta.hasDeinit;
const ManagedOpaqueWrapper = types.ManagedOpaqueWrapper;
const RegrexError = types.errors.ErrorSet;
const idleDestructor = ext.C_noOpDestructor;

const c_alloc = std.heap.c_allocator;

fn freeMatchCallback(alloc: std.mem.Allocator, value: *regrex.Match) void {
    value.deinit(alloc);
}
//
// /// C-compatible callback required to initialize the C buffer object
// fn freeManagedMatchCallback(item: *anyopaque) callconv(.c) void {
//     const slot: **regx_match_t = @ptrCast(@alignCast(item));
//
//     ManagedMatch.deinit(c_alloc, slot.*);
// }

fn freeIteratorCallback(alloc: std.mem.Allocator, value: *regrex.FindIterator) void {
    _ = alloc;
    value.deinit();
}

const ManagedMatch = ManagedOpaqueWrapper(regx_match_t, regrex.Match, freeMatchCallback);
const ManagedIterator = ManagedOpaqueWrapper(regx_iter_t, regrex.FindIterator, freeIteratorCallback);

/// Helps to avoid duplicating code
const PatternMatchMode = enum { match, search };

fn patternMatchImpl(
    // optimization trick: the mode is known statically at each call site;
    // so resolve the mode switch and specialize the function at compile time
    comptime mode: PatternMatchMode,
    alloc: std.mem.Allocator,
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    out_obj: ?*?*regx_match_t,
// convention: use actual Zig types for non-exported functions
) RegrexError!void {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before finding matches
    out_obj.* = null;

    const match = try switch(mode) {
        .match => p.match(std.mem.span(input)),
        .search => p.search(std.mem.span(input)),
    };

    out.* = try ManagedMatch.init(alloc, match);
}

/// Stable return code type used by the C ABI.
pub const regx_rcode_t = ext.C_ReturnCode;
/// Regular expression compile flags to modify pattern behaviour
pub const regx_flags_t = u8;
pub const regx_span_t = types.Span;
pub const regx_match_t = ext.C_MatchHolder;

export fn regx_match_destroy(match: ?*regx_match_t) callconv(.c) void {
    ManagedMatch.deinit(c_alloc, match);
}

/// Returns the start and end byte offsets of a capture group in input string
export fn regx_match_span(
    match: ?*const regx_match_t,
    i: usize,
    out: ?*regx_span_t
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out orelse return .REGREX_EARG;
    const owned = ManagedMatch.unwrapConst(m);

    span.* = owned.span(i) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}

/// Copies the bytes matched by capture group `i` into a byte buffer
export fn regx_match_group(
    match: ?*const regx_match_t,
    i: usize,
    out_str: ?*?[*:0]u8
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const out  = out_str orelse return .REGREX_EARG;
    out.* = null;

    const owned = ManagedMatch.unwrapConst(m);
    const group = owned.group(i) catch |err| {
        return conv.toErrorCode(err);
    };

    out.* = conv.toCString(c_alloc, group) catch |err| return conv.toErrorCode(err);
    return .OK;
}

/// Copies the bytes of the full match into a byte buffer
export fn regx_match_full(match: ?*const regx_match_t, out_str: ?*?[*:0]u8) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_str orelse return .REGREX_EARG;
    out.* = null;

    const owned = ManagedMatch.unwrapConst(m);
    const full_match = owned.group(0) catch |err| {
        return conv.toErrorCode(err);
    };

    out.* = conv.toCString(full_match) catch |err| return conv.toErrorCode(err);
    return .OK;
}

/// Copies all groups (byte offsets) except the first one into a buffer
export fn regx_match_subgroups(
    match: ?*const regx_match_t,
    out_arr: ?[*]*regx_span_t,
    out_size: ?*usize,
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const arr = out_arr orelse return .REGREX_EARG;
    const arr_size = out_size orelse return .REGREX_EARG;

    arr.* = null;
    arr_size.* = 0;

    const owned = ManagedMatch.unwrapConst(m);
    const subgroups = owned.subgroups();
    const groups_count = subgroups.len;

    conv.toCArray(regx_span_t, c_alloc, subgroups, arr) catch |err| return conv.toErrorCode(err);

    arr_size.* = groups_count;
    return .OK;
}

pub const regx_iter_t = ext.C_IterHolder;

/// `regx_iter_t` destructor.
///
/// Passing `null` is valid and has no effect.
///
/// Matches already produced by the iterator are not destroyed
/// and must be released separately.
export fn regx_iter_destroy(iter: ?*regx_iter_t) callconv(.c) void {
    ManagedIterator.deinit(c_alloc, iter);
}

/// Perform lookup iteration once; store result at `out_obj`.
///
/// If Match is found, it must be released. If the iterator is exhausted, stores `null`
/// at `out_obj` and returns `.REGREX_ENOMATCH`
export fn regx_iter_next(iter: ?*regx_iter_t, out_obj: ?*?*regx_match_t) callconv(.c) regx_rcode_t {
    const i = iter orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const owned = ManagedIterator.unwrap(i);
    const match = (owned.next() catch |err| {
        return conv.toErrorCode(err);
    }) orelse return .REGREX_ENOMATCH;

    const wrapped = ManagedMatch.init(c_alloc, match) catch |err| {
        match.deinit(c_alloc);
        return conv.toErrorCode(err);
    };
    out.* = wrapped;

    return .OK;
}

/// Opaque handler for compiled reusable regex pattern.
///
/// It is allocated on the heap and must be released
pub const regx_pattern_t = regrex.Pattern;

export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) callconv(.c) void {
    const p = pattern orelse return;
    p.deinit();
}

export fn regx_pattern_match(
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    patternMatchImpl(.match, c_alloc, pattern, input, out_obj) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_search(
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    patternMatchImpl(.search, c_alloc, pattern, input, out_obj) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_find_iter(
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    out_obj: ?*?*regx_iter_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before creating iterator
    out.* = null;

    const iter = p.findIter(std.mem.span(input)) catch |err| {
        return conv.toErrorCode(err);
    };

    out.* = ManagedIterator.init(c_alloc, iter) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_find_all(
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    out_arr: ?*?[*]*regx_match_t,
    out_size: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const arr = out_arr orelse return .REGREX_EARG;
    const arr_size = out_size orelse return .REGREX_EARG;

    arr.* = null;
    arr_size.* = 0;

    const matches = p.findAll(std.mem.span(input)) catch |err| return conv.toErrorCode(err);
    const match_count = matches.len;

    conv.toCArrayWrapped(
        regrex.Match,
        *regx_match_t,
        ManagedMatch,
        c_alloc,
        matches,
        freeMatchCallback,
        arr,
    ) catch |err| return conv.toErrorCode(err);

    arr_size.* = match_count;
    return .OK;
}

export fn regx_pattern_sub(
    pattern: ?*const regx_pattern_t,
    input: [*:0]const u8,
    repl: [*:0]const u8,
    count: usize,
    out_str: ?*?[*:0]u8,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_str orelse return .REGREX_EARG;
    out.* = null;

    const sub = p.sub(std.mem.span(input), std.mem.span(repl), .{ .count = count }) catch |err| {
        return conv.toErrorCode(err);
    };
    const result = conv.toCString(c_alloc, sub) catch |err| return conv.toErrorCode(err);

    out.* = result;
    return .OK;
}

export fn regrex_compile(
    pattern: ?[*:0]const u8,
    flags: regx_flags_t,
    out_obj: ?*?*regx_pattern_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;
    const compiled = regrex.compile(c_alloc, p, conv.bitmaskToFlags(flags)) catch |err| {
        return conv.toErrCode(err);
    };
    out.* = compiled;
    return .OK;
}
