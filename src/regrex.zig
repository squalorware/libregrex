const lib = @import("lib");
const cast = lib.cast;
const ctypes = lib.ctypes;
const helpers = lib.helpers;
const mem = lib.mem;
const regex = lib.regex;

const Allocator = mem.Allocator;
const c_allocator = mem.c_allocator;


/// A helper to release matches and their capture groups in array of opaques
fn freeCMatchCallback(alloc: Allocator, ptr: **regx_match_t) void {
    const m = ptr.*;
    MatchInterface.destroy(m, alloc);
}

/// Return codes used within the library
pub const regx_rcode_t = ctypes.Rcode;

/// Regex flags as a bitmask
pub const regx_flags_t = u8;

/// Byte offset within the input string. Represents match data (full match and capture groups).
///     Follows slice semantics: `.start` is inclusive; `.end` is exclusive.
pub const regx_span_t = regex.Span;

/// Releases an array of byte offset ranges
pub export fn regx_span_buffer_free(ptr: ?[*]regx_span_t, len: usize) callconv(.c) void {
    _ = mem.freeRaw(regx_span_t, c_allocator, ptr, len, null);
}

/// Opaque type pointing to data structure that stores the matching result as a buffer of byte offsets
pub const regx_match_t = opaque {};

/// Proxy handler between `regx_match_t` and `regrex.Match`
const MatchInterface = helpers.initOpaqueInterface(
    regex.Match,
    regx_match_t,
    mem.freeMatchCallback
);

pub export fn regx_match_destroy(match: ?*regx_match_t) callconv(.c) void {
    const ptr = match orelse return;
    MatchInterface.destroy(ptr, c_allocator);
}

/// Releases an array of matches and their capture groups
pub export fn regx_match_buffer_free(ptr: ?*?[*]*regx_match_t, len: usize) void {
    const buf = ptr orelse return;
    const matches = buf.* orelse return;

    _ = mem.freeRaw(*regx_match_t, c_allocator, matches, len, freeCMatchCallback);
}

/// Retrieves a capture group at `i`;
pub export fn regx_match_span(match: ?*regx_match_t, i: usize, out_p: ?*regx_span_t) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out_p orelse return .REGREX_EARG;

    const unwrapped = MatchInterface.unwrap(m) catch |err| {
        return cast.toReturnCode(err);
    };
    span.* = unwrapped.span(i) catch |err| return cast.toReturnCode(err);

    return .OK;
}

/// Saves a substring of input outlined by byte offset at `i` to a NULL-terminated buffer
pub export fn regx_match_group(
    match: ?*regx_match_t,
    i: usize,
    out_buf: ?*?ctypes.Str,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buf = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    buf.* = null;
    len.* = 0;

    const unwrapped = MatchInterface.unwrap(m) catch |err| {
        return cast.toReturnCode(err);
    };

    const group = unwrapped.group(i) catch |err| {
        return cast.toReturnCode(err);
    };
    const group_len = group.len;

    buf.* = cast.toCString(c_allocator, group) catch |err| return cast.toReturnCode(err);
    len.* = group_len;
    return .OK;
}

/// Allocates a a NULL-terminated buffer, stores in it a copy of the full match string
pub export fn regx_match_full(match: ?*regx_match_t, out_buf: ?*?ctypes.Str, out_len: ?*usize) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buf = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    buf.* = null;
    len.* = 0;

    const unwrapped = MatchInterface.unwrap(m) catch |err| {
        return cast.toReturnCode(err);
    };

    const full_match = unwrapped.full() catch |err| {
        return cast.toReturnCode(err);
    };
    const fm_len = full_match.len;

    buf.* = cast.toCString(c_allocator, full_match) catch |err| {
        return cast.toReturnCode(err);
    };
    len.* = fm_len;
    return .OK;
}

/// Returns the capture groups of the match excluding the full match at `groups[0]`
pub export fn regx_match_subgroups(match: ?*regx_match_t, out_buf: ?*?[*]regx_span_t, out_len: ?*usize) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buf = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    const unwrapped = MatchInterface.unwrap(m) catch |err| return cast.toReturnCode(err);
    const result = unwrapped.subgroups() catch |err| return cast.toReturnCode(err);

    buf.* = result.ptr;
    len.* = result.len;

    return .OK;
}

/// Lazy iterator over matches
pub const regx_iter_t = regex.FindIterator;

pub export fn regx_iter_destroy(iter: ?*regx_iter_t) callconv(.c) void {
    const iterator = iter orelse return;
    iterator.deinit(c_allocator);
}

/// Scans the input once, starting at position in provided context,
/// then increments it by one UTF-8 codepoint byte length
pub export fn regx_iter_next(iter: ?*regx_iter_t, out_p: ?*?*regx_match_t) callconv(.c) regx_rcode_t {
    var iterator = iter orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;

    const match = (iterator.next(c_allocator) catch |err| {
        return cast.toReturnCode(err);
    }) orelse return .REGREX_ENOMATCH;

    out.* = MatchInterface.create(c_allocator, match) catch |err| {
        return cast.toReturnCode(err);
    };
    return .OK;
}

/// Opaque type representing the compiled regex pattern
pub const regx_pattern_t = regex.Pattern;

pub export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) callconv(.c) void {
    const p = pattern orelse return;
    p.deinit();
}

/// Retrieves the first match encountered at the start of `in_str`
pub export fn regx_pattern_match(
    pattern: ?*regx_pattern_t,
    in_str: ?ctypes.ConstStr,
    out_p: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    const out = out_p orelse return .REGREX_EARG;
    const m = helpers.commonMatchImpl(
        .match,
        .pattern,
        c_allocator,
        pattern,
        in_str
    ) catch |err| return cast.toReturnCode(err);

    out.* = MatchInterface.create(c_allocator, m) catch |err| {
        return cast.toReturnCode(err);
    };
    return .OK;
}

/// Retrieves the first match found at any position within `in_str`
pub export fn regx_pattern_search(
    pattern: ?*regx_pattern_t,
    in_str: ?ctypes.ConstStr,
    out_p: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    const out = out_p orelse return .REGREX_EARG;
    const m = helpers.commonMatchImpl(
        .search,
        .pattern,
        c_allocator,
        pattern,
        in_str
    ) catch |err| return cast.toReturnCode(err);

    out.* = MatchInterface.create(c_allocator, m) catch |err| {
        return cast.toReturnCode(err);
    };
    return .OK;
}

/// Initializes the lazy iterator
pub export fn regx_pattern_find_iter(
    pattern: ?*regx_pattern_t,
    in_str: ?ctypes.ConstStr,
    out_p: ?*?*regx_iter_t,
) callconv(.c) regx_rcode_t {
    var p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before creating iterator
    out.* = null;

    const iter = p.findIter(mem.span(input)) catch |err| {
        return cast.toReturnCode(err);
    };

    out.* = iter;
    return .OK;
}

/// Allocates a buffer and writes all non-overlapping matches to it
pub export fn regx_pattern_find_all(
    pattern: ?*regx_pattern_t,
    in_str: ?ctypes.ConstStr,
    out_buf: ?*?[*]*regx_match_t,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const arr = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    arr.* = null;
    len.* = 0;

    const matches = p.findAll(mem.span(input)) catch |err| {
        return cast.toReturnCode(err);
    };
    const mlen = matches.len;

    var buffer = c_allocator.alloc(*regx_match_t, mlen) catch {
        return .REGREX_EMALLOC;
    };
    errdefer c_allocator.free(buffer);

    for (matches, 0..) |m, i| {
        buffer[i] = MatchInterface.create(c_allocator, m) catch |err| {
            return cast.toReturnCode(err);
        };
    }

    arr.* = buffer.ptr;
    len.* = buffer.len;

    return .OK;
}

/// Copies the input string, then substitutes all matches with a replacement string
///
/// Writes result into an allocated NULL-terminated buffer
pub export fn regx_pattern_sub(
    pattern: ?*regx_pattern_t,
    in_str: ?ctypes.ConstStr,
    repl_str: ?ctypes.ConstStr,
    count: usize,
    out_buf: ?*?ctypes.Str,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const repl = repl_str orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;

    out.* = null;
    len.* = 0;

    const replaced: []u8 = p.sub(mem.span(input), mem.span(repl),.{ 
        .count = count 
    }) catch |err| return cast.toReturnCode(err);

    const repl_len = replaced.len;
    defer mem.freeAlloc(u8, c_allocator, replaced, null);

    out.* = cast.toCString(c_allocator, replaced) catch |err| {
        return cast.toReturnCode(err);
    };
    len.* = repl_len;
    return .OK;
}

pub export fn regrex_str_free(ptr: ?ctypes.Str, len: usize) callconv(.c) void {
    _ = mem.freeRaw(u8, c_allocator, ptr, len, null);
}

/// Retrieves a human-readable error message from the return code.
///
/// Returned string is not allocated and does not need to be released
pub export fn regrex_error(rcode: regx_rcode_t) callconv(.c) ctypes.ConstStr {
    return cast.toErrorMsg(rcode);
}

/// Compiles regular expression pattern string
///
/// Provides a pointer to an opaque type encapsulating the compiled pattern data and exposing a public interface
pub export fn regrex_compile(
    pattern: ?ctypes.ConstStr,
    cflags: regx_flags_t,
    out_p: ?*?*regx_pattern_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_p orelse return .REGREX_EARG;
    const flags = regex.Flags.fromIntBitmask(cflags);
    out.* = null;

    const compiled = regex.compile(c_allocator, mem.span(p), flags) catch |err| {
        return cast.toReturnCode(err);
    };

    out.* = compiled;
    return .OK;
}

/// One-off lookup for the first match at the beginning of the input
pub export fn regrex_match(
    pattern: ?ctypes.ConstStr, 
    in_str: ?ctypes.ConstStr, 
    cflags: regx_flags_t, 
    out_p: ?*?*regx_match_t
) callconv(.c) regx_rcode_t {

    const out = out_p orelse return .REGREX_EARG;
    const flags = regex.Flags.fromIntBitmask(cflags);

    const m = helpers.commonMatchImpl(
        .match,
        .root,
        c_allocator,
        .{ .pattern = pattern, .flags = flags },
        in_str
    ) catch |err| return cast.toReturnCode(err);

    out.* = MatchInterface.create(c_allocator, m) catch |err| {
        return cast.toReturnCode(err);
    };
    return .OK;
}

/// One-off lookup for the first match at any position within the input
pub export fn regrex_search(
    pattern: ?ctypes.ConstStr, 
    in_str: ?ctypes.ConstStr, 
    cflags: regx_flags_t, 
    out_p: ?*?*regx_match_t
) callconv(.c) regx_rcode_t {

    const out = out_p orelse return .REGREX_EARG;
    const flags = regex.Flags.fromIntBitmask(cflags);

    const m = helpers.commonMatchImpl(
        .match,
        .root,
        c_allocator,
        .{ .pattern = pattern, .flags = flags },
        in_str
    ) catch |err| return cast.toReturnCode(err);

    out.* = MatchInterface.create(c_allocator, m) catch |err| {
        return cast.toReturnCode(err);
    };
    return .OK;
}

/// One-off lookup for all non-overlapping matches within the input
pub export fn regrex_find_all(
    pattern: ?ctypes.ConstStr,
    in_str: ?ctypes.ConstStr,
    cflags: regx_flags_t,
    out_buf: ?*?[*]*regx_match_t,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const flags = regex.Flags.fromIntBitmask(cflags);

    const arr = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;
    arr.* = null;
    len.* = 0;

    const matches = regex.findAll(
        c_allocator,
        mem.span(p),
        mem.span(input),
        flags,
    ) catch |err| return cast.toReturnCode(err);
    const mlen = matches.len;

    var buffer = c_allocator.alloc(*regx_match_t, mlen) catch {
        return .REGREX_EMALLOC;
    };
    errdefer c_allocator.free(buffer);

    for (matches, 0..) |m, i| {
        buffer[i] = MatchInterface.create(c_allocator, m) catch |err| {
            return cast.toReturnCode(err);
        };
    }

    arr.* = buffer.ptr;
    len.* = buffer.len;
    return .OK;
}

/// One-off substitution of matches in the input with a replacement string.
///
/// Allocates a copy, does not mutate the input
pub export fn regrex_sub(
    pattern: ?ctypes.ConstStr,
    in_str: ?ctypes.ConstStr,
    repl_str: ?ctypes.ConstStr,
    cflags: regx_flags_t,
    count: usize,
    out_buf: ?*?ctypes.Str,
    out_len: ?*usize,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const input = in_str orelse return .REGREX_EARG;
    const repl = repl_str orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const len = out_len orelse return .REGREX_EARG;
    out.* = null;
    len.* = 0;

    const flags = regex.Flags.fromIntBitmask(cflags);
    const options = lib.SubOptions{
        .ignore_case = flags.ignore_case,
        .multiline = flags.multiline,
        .dot_all = flags.dot_all,
        ._padding = flags._padding,
        .count = count,
    };

    const replaced = regex.sub(
        c_allocator,
        mem.span(p),
        mem.span(input),
        mem.span(repl),
        options
    ) catch |err| return cast.toReturnCode(err);

    const repl_len = replaced.len;

    out.* = cast.toCString(c_allocator, replaced) catch |err| {
        return cast.toReturnCode(err);
    };
    len.* = repl_len;
    return .OK;
}
