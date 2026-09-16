const std = @import("std");
const lib = @import("lib");
const C = lib.C;
const c_alloc = std.heap.c_allocator;

/// Return codes used within the library
pub const regx_rcode_t = C.ReturnCode;
/// Regex flags as a bitmask
pub const regx_flags_t = u8;

pub const regx_span_t = lib.RegrexSpan;

/// Releases an array of byte offset ranges
export fn regx_span_buf_free(ptr: ?[*]regx_span_t, len: usize) callconv(.c) void {
    _ = C.freeBuffer(regx_span_t, c_alloc, ptr, len, null);
}

pub const regx_match_t = C.Match;

export fn regx_match_destroy(match: ?*regx_match_t) callconv(.c) void {
    const m = match orelse return;
    m.destroy(c_alloc);
}

/// Releases an array of matches and their capture groups
export fn regx_match_buf_free(ptr: ?*?[*]regx_match_t, len: usize) void {
    const matches = ptr orelse return;

    _ = C.freeBuffer(regx_match_t, c_alloc, matches.*, len, C.freeCMatchCallback);
}

/// Retrieves a capture group at `cgroups[i]`;
export fn regx_match_span(match: ?*regx_match_t, i: usize, out_p: ?*regx_span_t) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out_p orelse return .REGREX_EARG;

    const captures = m.cgroups[0..m.groups_len];
    span.* = captures[i];

    return .OK;
}

/// Returns a substring of input outlined by byte offset at `cgroups[i]`
export fn regx_match_group(
    match: ?*regx_match_t,
    i: usize,
    out_buf: ?*?C.String,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buf  = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;
    
    buf.* = null;
    len.* = 0;

    const unwrapped = m.unwrap() catch |err| {
        return lib.toErrorCode(err);
    };
    // const owned = lib.ManagedMatch.unwrapConst(m);
    const group = unwrapped.group(i) catch |err| {
        return lib.toErrorCode(err);
    };
    const group_len = group.len;

    buf.* = C.toString(c_alloc, group) catch |err| return lib.toErrorCode(err);
    len.* = group_len;
    return .OK;
}

/// Allocates a a NULL-terminated buffer, stores in it a copy of the full match
export fn regx_match_full(match: ?*regx_match_t, out_buf: ?*?C.String, out_len: ?*usize) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buf = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    buf.* = null;
    len.* = 0;

    const unwrapped = m.unwrap() catch |err| {
        return lib.toErrorCode(err);
    };

    const full_match = unwrapped.full() catch |err| {
        return lib.toErrorCode(err);
    };
    const fm_len = full_match.len;

    buf.* = C.toString(c_alloc, full_match) catch |err| return lib.toErrorCode(err);
    len.* = fm_len;
    return .OK;
}

/// Returns the capture groups of the match excluding the full match at `cgroups[0]`
export fn regx_match_subgroups(m: ?*regx_match_t, out_buf: ?*?[*]regx_span_t, out_len: ?*usize) callconv(.c) regx_rcode_t {
    const match = m orelse return .REGREX_EARG;
    const buf = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    buf.* = match.cgroups[1..];
    len.* = match.groups_len - 1;
    return .OK;
}

pub const regx_iter_t = lib.RegrexIterator;

export fn regx_iter_destroy(iter: ?*regx_iter_t) callconv(.c) void {
    const iterator = iter orelse return;
    iterator.deinit(c_alloc);
}

/// Scans the input once, starting at position in current context, 
/// then advances position register by one UTF-8 codepoint bytelength
export fn regx_iter_next(iter: ?*regx_iter_t, out_p: ?*regx_match_t) callconv(.c) regx_rcode_t {
    var iterator = iter orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;

    const match = (iterator.next() catch |err| {
        return lib.toErrorCode(err);
    }) orelse return .REGREX_ENOMATCH;

    out.* = C.Match.create(c_alloc, match) catch |err| {
        return lib.toErrorCode(err);
    };
    return .OK;
}

/// Represents the compiled regex pattern. Owns the bytecode buffer executed by internal VM. 
///    Has no public fields and is immutable. Provides a public API for user operations. 
///    Can only be created by compiling the pattern, and discarded
pub const regx_pattern_t = lib.RegrexPattern;

export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) callconv(.c) void {
    const p = pattern orelse return;
    p.deinit();
}
/// Retrieves the first match encountered moving from the input start
export fn regx_pattern_match(
    pattern: ?*regx_pattern_t,
    in_str: ?C.StaticString,
    out_p: ?*regx_match_t,
) callconv(.c) regx_rcode_t {
    _ = lib.commonMatchImpl(
        .match,
        .pattern,
        c_alloc,
        pattern,
        in_str,
        out_p
    ) catch |err| return lib.toErrorCode(err);

    return .OK;
}
/// Retrieves the first match found anywhere in input
export fn regx_pattern_search(
    pattern: ?*regx_pattern_t,
    in_str: ?C.StaticString,
    out_p: ?*regx_match_t,
) callconv(.c) regx_rcode_t {
    _ = lib.commonMatchImpl(
        .search,
        .pattern,
        c_alloc,
        pattern,
        in_str,
        out_p
    ) catch |err| return lib.toErrorCode(err);

    return .OK;
}

/// Initializes the lazy iterator
export fn regx_pattern_find_iter(
    pattern: ?*regx_pattern_t,
    in_str: ?C.StaticString,
    out_p: ?*?*regx_iter_t,
) callconv(.c) regx_rcode_t {
    var p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before creating iterator
    out.* = null;

    const iter = p.findIter(std.mem.span(input)) catch |err| {
        return lib.toErrorCode(err);
    };

    out.* = iter;
    return .OK;
}

/// Allocates a buffer and stores in it all non-overlapping matches
export fn regx_pattern_find_all(
    pattern: ?*regx_pattern_t,
    in_str: ?C.StaticString,
    out_buf: ?*?[*]regx_match_t,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const arr = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    arr.* = null;
    len.* = 0;

    const matches = p.findAll(std.mem.span(input)) catch |err| {
        return lib.toErrorCode(err);
    };
    const mlen = matches.len;
    defer lib.freeAny(lib.RegrexMatch, c_alloc, matches[0..mlen], lib.freeMatchCallback);

    var buffer = c_alloc.alloc(C.Match, mlen) catch {
        return .REGREX_EMALLOC;
    };
    errdefer c_alloc.free(buffer);

    for (matches, 0..) |m, i| {
        buffer[i] = C.Match.create(c_alloc, m) catch |err| {
            return lib.toErrorCode(err);
        };
    }

    arr.* = buffer.ptr;
    len.* = buffer.len;

    return .OK;
}

/// Copies the input string, then substitutes all matches with a replacement string 
///
/// Writes result into an allocated NULL-terminated buffer
export fn regx_pattern_sub(
    pattern: ?*regx_pattern_t,
    in_str: ?C.StaticString,
    repl_str: ?C.StaticString,
    count: usize,
    out_buf: ?*?C.String,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const repl = repl_str orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    out.* = null;
    len.* = 0;

    const replaced: []u8 = p.sub(
        std.mem.span(input), 
        std.mem.span(repl),
        .{ .count = count },
    ) catch |err| {
        return lib.toErrorCode(err);
    };
    const repl_len = replaced.len;
    defer lib.freeAny(u8, c_alloc, replaced, null);

    out.* = C.toString(c_alloc, replaced) catch |err| return lib.toErrorCode(err);
    len.* = repl_len;
    return .OK;
}

export fn regrex_str_free(ptr: ?C.String, len: usize) callconv(.c) void {
    _ = C.freeBuffer(u8,c_alloc, ptr, len, null);
}

/// Retrieve a human-readable error message from the return code. 
/// 
/// Returned string is not allocated and does not need to be released
export fn regrex_error(rcode: regx_rcode_t) callconv(.c) C.StaticString {
    return C.toErrorMsg(rcode);
}

/// Compiles regular expression pattern string 
/// 
/// Provides a pointer to an opaque type encapsulating the compiled pattern data and exposing a public interface
export fn regrex_compile(pattern: ?C.StaticString, flags: regx_flags_t, out_p: ?*?*regx_pattern_t,) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;
    out.* = null;

    const compiled = lib.regrexCompile(
        c_alloc,
        std.mem.span(p),
        lib.toCompileFlags(flags)
    ) catch |err| return lib.toErrorCode(err);

    out.* = compiled;
    return .OK;
}

/// One-off lookup for the first match at the beginning of the input
export fn regrex_match(
    pattern: ?C.StaticString,
    in_str: ?C.StaticString,
    flags: regx_flags_t,
    out_p: ?*regx_match_t
) callconv(.c) regx_rcode_t {
    _ = lib.commonMatchImpl(
        .match,
        .root,
        c_alloc,
        lib.LookupCtx{ .pattern = pattern, .flags = flags },
        in_str,
        out_p,
    ) catch |err| return lib.toErrorCode(err);

    return .OK;
}

/// One-off lookup for the first match at any position within the input
export fn regrex_search(
    pattern: ?C.StaticString,
    in_str: ?C.StaticString,
    flags: regx_flags_t,
    out_p: ?*regx_match_t
) callconv(.c) regx_rcode_t {
    _ = lib.commonMatchImpl(
        .search,
        .root,
        c_alloc,
        lib.LookupCtx{ .pattern = pattern, .flags = flags },
        in_str,
        out_p,
    ) catch |err| return lib.toErrorCode(err);

    return .OK;
}

/// One-off lookup for all non-overlapping matches within the input
export fn regrex_find_all(
    pattern: ?C.StaticString,
    in_str: ?C.StaticString,
    flags: regx_flags_t,
    out_buf: ?*?[*]regx_match_t,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const arr = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    arr.* = null;
    len.* = 0;

    const matches = lib.regrexFindAll(
        c_alloc,
        std.mem.span(p),
        std.mem.span(input),
        lib.toCompileFlags(flags),
    ) catch |err| return lib.toErrorCode(err);
    const mlen = matches.len;

    defer lib.freeAny(lib.RegrexMatch, c_alloc, matches[0..mlen], lib.freeMatchCallback);

    var buffer = c_alloc.alloc(C.Match, mlen) catch {
        return .REGREX_EMALLOC;
    };
    errdefer c_alloc.free(buffer);

    for (matches, 0..) |m, i| {
        buffer[i] = C.Match.create(c_alloc, m) catch |err| {
            return lib.toErrorCode(err);
        };
    }

    arr.* = buffer.ptr;
    len.* = buffer.len;
    return .OK;
}

/// One-off substitution of matches in the input with a replacement string.
/// 
/// Allocates a copy, does not mutate the input 
export fn regrex_sub(
    pattern: ?C.StaticString,
    in_str: ?C.StaticString,
    repl_str: ?C.StaticString,
    flags: regx_flags_t,
    count: usize,
    out_buf: ?*?C.String,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const repl = repl_str orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;
    out.* = null;
    len.* = 0;

    const cflags = lib.toCompileFlags(flags);
    const options = lib.SubOptions {
        .ignore_case = cflags.ignore_case,
        .multiline = cflags.multiline,
        .dot_all = cflags.dot_all,
        ._padding = cflags._padding,
        .count = count,
    };

    const replaced = lib.regrexSub(
        c_alloc,
        std.mem.span(p),
        std.mem.span(input),
        std.mem.span(repl),
        options
    ) catch |err| return lib.toErrorCode(err);
    const repl_len = replaced.len;

    out.* = C.toString(c_alloc, replaced) catch |err| {
        return lib.toErrorCode(err);
    };
    len.* = repl_len;
    return .OK;
}
