const std = @import("std");
const regrex = @import("regrex");
const lib = @import("lib");
const RegrexError = regrex.RegrexError;

const c_alloc = std.heap.c_allocator;

/// Wrapper over string pattern and compilation flags
/// to ensure common API for both `Pattern.match`/`Pattern.search` and root `match`/`search`
const LookupCtx = struct {
    pattern: lib.C_StringPtr,
    flags: regx_flags_t,
};
/// Library function to call
const LookupFn = enum { match, search };
/// Library module containing the function to call
const LookupSource = enum { root, pattern };

/// A callable wrapper over the logic common for calling either of
/// `regrex.match`, `regrex.search`, `regrex.Pattern.match` or `regrex.Pattern.search`
fn commonMatchImpl(
    comptime Fn: LookupFn,
    comptime S: LookupSource,
    alloc: std.mem.Allocator,
    subject: anytype,
    input: lib.C_StringPtr,
    out_obj: ?*?*regx_match_t,
) RegrexError!void {
    const in = input orelse return RegrexError.InvalidArgument;
    const out = out_obj orelse return RegrexError.InvalidArgument;

    // Ensure that output pointer is null if function fails before finding matches
    out.* = null;

    const match = if (comptime S == .pattern) blk: {
        const pattern: *regrex.Pattern = subject orelse return RegrexError.InvalidArgument;

        break :blk try switch(Fn) {
            .match => pattern.match(std.mem.span(in)),
            .search => pattern.search(std.mem.span(in)),
        };
    } else blk: {
        const pattern: lib.C_StringPtr = subject.pattern orelse return RegrexError.InvalidArgument;

        break :blk try switch(Fn) {
            .match => regrex.match(alloc, std.mem.span(pattern), std.mem.span(in), lib.toCompileFlags(subject.flags)),
            .search => regrex.search(alloc, std.mem.span(pattern), std.mem.span(in), lib.toCompileFlags(subject.flags)),
        };
    } orelse return RegrexError.NoMatch;

    out.* = try lib.ManagedMatch.init(alloc, match);
}

/// Stable return code type used by the C ABI.
pub const regx_rcode_t = lib.C_ReturnCode;
/// Regular expression compile flags to modify pattern behaviour
pub const regx_flags_t = u8;
pub const regx_span_t = lib.Span;
pub const regx_match_t = lib.C_MatchHolder;

export fn regx_match_destroy(match: ?*regx_match_t) callconv(.c) void {
    lib.ManagedMatch.deinit(c_alloc, match);
}

/// Returns the start and end byte offsets of a capture group in input string
export fn regx_match_span(
    match: ?*const regx_match_t,
    i: usize,
    out: ?*regx_span_t
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out orelse return .REGREX_EARG;
    const owned = lib.ManagedMatch.unwrapConst(m);

    span.* = owned.span(i) catch |err| {
        return lib.toErrorCode(err);
    };
    return .OK;
}

/// Copies the bytes matched by capture group `i` into a byte buffer
export fn regx_match_group(
    match: ?*const regx_match_t,
    i: usize,
    out_str: lib.C_MutableStringPtr,
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const out  = out_str orelse return .REGREX_EARG;
    out.* = null;

    const owned = lib.ManagedMatch.unwrapConst(m);
    const group = owned.group(i) catch |err| {
        return lib.toErrorCode(err);
    };

    out.* = lib.toC_String(c_alloc, group) catch |err| return lib.toErrorCode(err);
    return .OK;
}

/// Copies the bytes of the full match into a byte buffer
export fn regx_match_full(match: ?*const regx_match_t, out_str: lib.C_MutableStringPtr) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_str orelse return .REGREX_EARG;
    out.* = null;

    const owned = lib.ManagedMatch.unwrapConst(m);
    const full_match = owned.group(0) catch |err| {
        return lib.toErrorCode(err);
    };

    out.* = lib.toC_String(full_match) catch |err| return lib.toErrorCode(err);
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

    const owned = lib.ManagedMatch.unwrapConst(m);
    const subgroups = owned.subgroups();
    const groups_count = subgroups.len;

    lib.toC_Array(regx_span_t, c_alloc, subgroups, arr) catch |err| return lib.toErrorCode(err);

    arr_size.* = groups_count;
    return .OK;
}

pub const regx_iter_t = lib.C_IterHolder;

/// `regx_iter_t` destructor.
///
/// Passing `null` is valid and has no effect.
///
/// Matches already produced by the iterator are not destroyed
/// and must be released separately.
export fn regx_iter_destroy(iter: ?*regx_iter_t) callconv(.c) void {
    lib.ManagedIterator.deinit(c_alloc, iter);
}

/// Perform lookup iteration once; store result at `out_obj`.
///
/// If Match is found, it must be released. If the iterator is exhausted, stores `null`
/// at `out_obj` and returns `.REGREX_ENOMATCH`
export fn regx_iter_next(iter: ?*regx_iter_t, out_obj: ?*?*regx_match_t) callconv(.c) regx_rcode_t {
    const i = iter orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const owned = lib.ManagedIterator.unwrap(i);
    const match = (owned.next() catch |err| {
        return lib.toErrorCode(err);
    }) orelse return .REGREX_ENOMATCH;

    const wrapped = lib.ManagedMatch.init(c_alloc, match) catch |err| {
        match.deinit(c_alloc);
        return lib.toErrorCode(err);
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
    input: lib.C_StringPtr,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    commonMatchImpl(.pattern, .match, c_alloc, pattern, input, out_obj) catch |err| {
        return lib.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_search(
    pattern: ?*const regx_pattern_t,
    input: lib.C_StringPtr,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    commonMatchImpl(.pattern, .search, c_alloc, pattern, input, out_obj) catch |err| {
        return lib.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_find_iter(
    pattern: ?*const regx_pattern_t,
    input: lib.C_StringPtr,
    out_obj: ?*?*regx_iter_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before creating iterator
    out.* = null;

    const iter = p.findIter(std.mem.span(input)) catch |err| {
        return lib.toErrorCode(err);
    };

    out.* = lib.ManagedIterator.init(c_alloc, iter) catch |err| {
        return lib.toErrorCode(err);
    };
    return .OK;
}

export fn regx_pattern_find_all(
    pattern: ?*const regx_pattern_t,
    input: lib.C_StringPtr,
    out_arr: ?*?[*]*regx_match_t,
    out_size: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const arr = out_arr orelse return .REGREX_EARG;
    const arr_size = out_size orelse return .REGREX_EARG;

    arr.* = null;
    arr_size.* = 0;

    const matches = p.findAll(std.mem.span(input)) catch |err| return lib.toErrorCode(err);
    const match_count = matches.len;

    lib.toC_ArrayWrapped(
        regrex.Match,
        *regx_match_t,
        lib.ManagedMatch,
        c_alloc,
        matches,
        lib.freeMatchCallback,
        arr,
    ) catch |err| return lib.toErrorCode(err);

    arr_size.* = match_count;
    return .OK;
}

export fn regx_pattern_sub(
    pattern: ?*const regx_pattern_t,
    input: lib.C_StringPtr,
    repl: lib.C_StringPtr,
    count: usize,
    out_str: lib.C_MutableStringPtr,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_str orelse return .REGREX_EARG;
    out.* = null;

    const replaced = p.sub(std.mem.span(input), std.mem.span(repl), .{ .count = count }) catch |err| {
        return lib.toErrorCode(err);
    };

    out.* = lib.toC_String(c_alloc, replaced) catch |err| return lib.toErrorCode(err);
    return .OK;
}

export fn regrex_error(rcode: regx_rcode_t) callconv(.c) lib.C_StringPtr {
    return lib.toErrorMsg(rcode).ptr;
}

export fn regrex_compile(
    pattern: lib.C_StringPtr,
    flags: regx_flags_t,
    out_obj: ?*?*regx_pattern_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;
    const compiled = regrex.compile(c_alloc, std.mem.span(p), lib.toCompileFlags(flags)) catch |err| {
        return lib.toErrorCode(err);
    };
    out.* = compiled;
    return .OK;
}

export fn regrex_match(
    pattern: lib.C_StringPtr,
    in_str: lib.C_StringPtr,
    flags: regx_flags_t,
    out_obj: ?*?*regx_match_t
) callconv(.c) regx_rcode_t {
    commonMatchImpl(
        .root,
        .match,
        c_alloc,
        LookupCtx{ .pattern = pattern, .flags = flags },
        in_str,
        out_obj,
    ) catch |err| {
        return lib.toErrorCode(err);
    };

    return .OK;
}

export fn regrex_search(
    pattern: lib.C_StringPtr,
    in_str: lib.C_StringPtr,
    flags: regx_flags_t,
    out_obj: ?*?*regx_match_t
) callconv(.c) regx_rcode_t {
    commonMatchImpl(
        .root,
        .match,
        c_alloc,
        LookupCtx{ .pattern = pattern, .flags = flags },
        in_str,
        out_obj,
    ) catch |err| {
        return lib.toErrorCode(err);
    };

    return .OK;
}

export fn regrex_find_all(
    pattern: lib.C_StringPtr,
    in_str: lib.C_StringPtr,
    flags: regx_flags_t,
    out_arr: ?*?[*]*regx_match_t,
    out_size: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const arr = out_arr orelse return .REGREX_EARG;
    const arr_size = out_size orelse return .REGREX_EARG;

    arr.* = null;
    arr_size.* = 0;

    const matches = regrex.findAll(
        c_alloc,
        std.mem.span(p),
        std.mem.span(input),
        lib.toCompileFlags(flags),
    ) catch |err| return lib.toErrorCode(err);
    const match_count = matches.len;

    lib.toC_ArrayWrapped(
        regrex.Match,
        *regx_match_t,
        lib.ManagedMatch,
        c_alloc,
        matches,
        lib.freeMatchCallback,
        arr,
    ) catch |err| return lib.toErrorCode(err);

    arr_size.* = match_count;
    return .OK;
}

export fn regrex_sub(
    pattern: lib.C_StringPtr,
    in_str: lib.C_StringPtr,
    repl_str: lib.C_StringPtr,
    flags: regx_flags_t,
    count: usize,
    out_str: lib.C_MutableStringPtr,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const repl = repl_str orelse return .REGREX_EARG;
    const out = out_str orelse return .REGREX_EARG;
    out.* = null;

    const options = .{
        .flags = lib.toCompileFlags(flags),
        .count = count,
    };

    const replaced = regrex.sub(
        c_alloc,
        std.mem.span(p),
        std.mem.span(input),
        std.mem.span(repl),
        options
    ) catch |err| return lib.toErrorCode(err);

    out.* = lib.toC_String(c_alloc, replaced) catch |err| return lib.toErrorCode(err);
    return .OK;
}
