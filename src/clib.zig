//! `regrex` C ABI implementation.
//!
//! This module exposes a C-compatible interface around the Zig-native `regrex`
//! API. Converts C pointer/length pairs to borrowed Zig slices, maps Zig
//! errors to stable C return codes, and wraps Zig-owned values behind opaque C
//! handles.
//! 
//! The functions exposed in this module are public **ONLY** for documentation purposes 
//! and **should NOT** be used in Zig code.
//!
//! Memory ownership model:
//! 
//! - **Owned** `regx_buffer_t` (e.g. allocated by `regrex_sub`) 
//!   is destroyed with `regx_buffer_destroy()`.
//!   **Borrowed** `regx_buffer_t` should not be destroyed.
//! - `regx_pattern_t` is destroyed with `regx_pattern_destroy()`.
//! - `regx_match_t` is destroyed with `regx_match_destroy()`.
//! - `regx_match_list_t` is destroyed with `regx_match_list_destroy()`.
//! - `regx_iter_t` is destroyed with `regx_iter_destroy()`.
//!
//! All exported functions accept nullable pointer arguments and return
//! `REGREX_EARG` for missing required inputs.

const std = @import("std");
const regrex = @import("root.zig");
const FindIterator = @import("./vm.zig").FindIterator;
const Group = @import("./common/types.zig").Group;
const WrappedOpaque = @import("./opaque.zig").WrappedOpaque;

const c_alloc = std.heap.c_allocator;
const testing = std.testing;
const Match = regrex.Match;
const Pattern = regrex.Pattern;
const RegrexError = regrex.RegrexError;

//============================
// Exported C type definitions
//============================

/// Stable return code type used by the C ABI.
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

/// Byte span of a match inside the original input.
///
/// `start` is inclusive. `end` is exclusive. 
/// Both values are byte offsets, not UTF-8 scalar indices.
pub const regx_group_t = extern struct {
    start: usize,
    end: usize,
};

/// A convenience type to wrap a string as a byte buffer with a known length.
///
/// Can be a borrowed read-only buffer which doesn't own the memory
/// or owned (i.e. allocated) in which case it must be released.
///
/// A buffer with `null` pointer `ptr` and zero length is an empty buffer.
/// A buffer with `null` `ptr` and non-zero length is invalid
pub const regx_buffer_t = extern struct {
    ptr: ?[*]const u8,
    len: usize,
};

/// Opaque handler for result type produced by matching operations.
///
/// It is allocated on the heap and must be released.
pub const regx_match_t = opaque {};

///Opaque handler for a list of matches.
///
/// It is allocated on the heap and must be released.
pub const regx_match_list_t = opaque {};

/// Opaque handler for compiled reusable regex pattern.
///
/// It is allocated on the heap and must be released
pub const regx_pattern_t = regrex.Pattern;

/// Opaque handler for a lazy iterator created by the compiled pattern.
///
/// The parent pattern and input buffer must outlive the iterator.
///
/// It is allocated on the heap and must be released
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

fn freeIteratorCallback(
    alloc: std.mem.Allocator,
    value: *FindIterator,
) void {
    _ = alloc;
    value.deinit();
}

const WrappedMatch = WrappedOpaque(regx_match_t, Match, freeMatchCallback);
const WrappedMatchList = WrappedOpaque(regx_match_list_t, []Match, freeMatchListCallback);
const WrappedIterator = WrappedOpaque(regx_iter_t, FindIterator, freeIteratorCallback);

/// Stores a nullable `Match` result to a wrapped opaque handler.
///
/// On success, creates a `WrappedMatch` and stores result into it. 
/// Ownership of the match is transferred to `out_obj`. 
/// 
/// Returns `RegrexError.NoMatch` if given `Match` is null and stores `null` to `out_obj`.
/// 
/// If allocation failed, releases `Match` and returns correspondent error.
fn storeMatch(match: ?Match, out_obj: *?*regx_match_t) RegrexError!void {
    out_obj.* = null;

    var m = match orelse return RegrexError.NoMatch;

    const owned = WrappedMatch.create(c_alloc, m) catch |err| {
        m.deinit(c_alloc);
        return err;
    };

    out_obj.* = owned;
}

/// Stores the byte buffer to the convenience type `regx_buffer_t`.
/// 
/// On success transfers ownership to `out_obj`. 
/// The caller must release the buffer manually.
/// 
/// On failure releases buffer and sets 
/// output parameter structure fields 
/// to null and 0 respectively
fn storeBuffer(
    alloc: std.mem.Allocator,
    buf: []u8,
    out_buf: ?*regx_buffer_t,
) RegrexError!void {
    const out = out_buf orelse {
        return RegrexError.InvalidArgument;
    };
    out.* = .{
        .ptr = null,
        .len = 0,
    };

    if (buf.len == 0) {
        alloc.free(buf);
        return;
    }

    out.* = .{
        .ptr = buf.ptr,
        .len = buf.len,
    };
}

//==================================
// C-compatible API implementation
//==================================

/// `regx_match_t` destructor.
///
/// Passing `null` is valid and has no effect.
pub export fn regx_match_destroy(match: ?*regx_match_t) void {
    WrappedMatch.destroy(c_alloc, match);
}

/// Writes the number of captured groups in match to `out_i`.
///
/// Excludes group 0, which is the full match.
pub export fn regx_match_groups_len(match: ?*const regx_match_t, out_i: ?*usize) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_i orelse return .REGREX_EARG;
    const owned = WrappedMatch.unwrapConst(m);

    out.* = owned.value.groups().len;
    return .REGREX_OK;
}

/// Write the byte span of group `i` to `out_obj`.
///
/// Group 0 is the full match. Capturing groups start at index 1.
pub export fn regx_match_span(
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

/// Copies substring of input at byte span `i` 
/// to a `out_obj` buffer wrapper.
///
/// The buffer should be released with `regx_buffer_destroy()`.
pub export fn regx_match_group(
    match: ?*const regx_match_t,
    i: usize,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };

    const owned = WrappedMatch.unwrapConst(m);

    const result = owned.value.group(i) catch |err| {
        return toErrorCode(err);
    };
    const buf = c_alloc.dupe(u8, result) catch {
        return .REGREX_ENOSPACE;
    };

    storeBuffer(c_alloc, buf, out) catch |err| {
        c_alloc.free(buf);
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Copies the full matching string (group 0) 
/// to a `out_obj` buffer wrapper.
///
/// The buffer should be released with `regx_buffer_destroy()`.
pub export fn regx_match_full(
    match: ?*const regx_match_t,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };

    const owned = WrappedMatch.unwrapConst(m);

    const result = owned.value.full();
    const buf = c_alloc.dupe(u8, result) catch {
        return .REGREX_ENOSPACE;
    };

    storeBuffer(c_alloc, buf, out) catch |err| {
        c_alloc.free(buf);
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// `regx_match_list_t` destructor.
///
/// Passing `null` is valid and has no effect.
pub export fn regx_match_list_destroy(list: ?*regx_match_list_t) void {
    WrappedMatchList.destroy(c_alloc, list);
}

/// Writes the number of matches in list to `out_i`.
pub export fn regx_match_list_len(list: ?*const regx_match_list_t, out_i: ?*usize) regx_errcode_t {
    const out = out_i orelse return .REGREX_EARG;
    out.* = 0;
    const l = list orelse return .REGREX_EARG;
    const owned = WrappedMatchList.unwrapConst(l);

    out.* = owned.value.len;
    return .REGREX_OK;
}

/// Retrieves a byte span of group `group_idx` 
/// found in match located at `match_idx` in `list`.
///
/// Group 0 is the full match.
pub export fn regx_match_list_span(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    group_idx: usize,
    out_obj: ?*regx_group_t,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const owned = WrappedMatchList.unwrapConst(l);

    if (match_idx >= owned.value.len) return .REGREX_EBADGRP;

    const result = owned.value[match_idx].span(group_idx) catch |err| {
        return toErrorCode(err);
    };

    out.* = toExternGroup(result);
    return .REGREX_OK;
}

/// Copies substring of input at byte span `group_idx`
/// found in match located at `match_idx` in `list`
/// to the `out_obj` buffer wrapper.

/// The buffer should be released with `regx_buffer_destroy()`.
pub export fn regx_match_list_group(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    group_idx: usize,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };

    const owned = WrappedMatchList.unwrapConst(l);

    if (match_idx >= owned.value.len) return .REGREX_EBADGRP;

    const result = owned.value[match_idx].group(group_idx) catch |err| {
        return toErrorCode(err);
    };

    const buf = c_alloc.dupe(u8, result) catch {
        return .REGREX_ENOSPACE;
    };

    storeBuffer(c_alloc, buf, out) catch |err| {
        c_alloc.free(buf);
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Copies the full matching string (group 0)
/// of a match located at `match_idx` in `list`
/// to the `out_obj` buffer wrapper.
///
/// The buffer should be released with `regx_buffer_destroy()`.
pub export fn regx_match_list_full(
    list: ?*const regx_match_list_t,
    match_idx: usize,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const l = list orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };

    const owned = WrappedMatchList.unwrapConst(l);

    if (match_idx >= owned.value.len) return .REGREX_EBADGRP;

    const result = owned.value[match_idx].full();

    const buf = c_alloc.dupe(u8, result) catch {
        return .REGREX_ENOSPACE;
    };

    storeBuffer(c_alloc, buf, out) catch |err| {
        c_alloc.free(buf);
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// `regx_pattern_t` compiled pattern handler's destructor.
///
/// Passing `null` is valid and has no effect.
pub export fn regx_pattern_destroy(pattern: ?*regx_pattern_t) void {
    const p = pattern orelse return;
    p.deinit();
}

/// Searches input with the compiled pattern.
///
/// The returned match is stored to the `out_obj` 
/// and must be released with `regx_match_destroy()`.
///
/// Returns .REGX_ENOMATCH if no match found; 
/// `out_obj` is set to `null`
pub export fn regx_pattern_search(
    pattern: ?*const regx_pattern_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
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

/// Matches input against the compiled pattern 
/// starting from the beginning of the input.
///
/// The returned match is stored to the `out_obj` 
/// and must be released with `regx_match_destroy()`.
///
/// Returns .REGX_ENOMATCH if no match found; 
/// `out_obj` is set to `null`
pub export fn regx_pattern_match(
    pattern: ?*const regx_pattern_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    out.* = null;
    const match = p.match(input) catch |err| {
        return toErrorCode(err);
    };
    storeMatch(match, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Creates a lazy iterator over non-overlapping matches
/// from the compiled pattern.

/// Stores the iterator to `out_obj`. The iterator must be released
/// with `regx_iter_destroy()`. The pattern and the input must outlive it.
pub export fn regx_pattern_find_iter(
    pattern: ?*const regx_pattern_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_iter_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };
    out.* = null;

    const owned = WrappedIterator.create(
        c_alloc, 
        p.findIter(input
    )) catch |err| {
        return toErrorCode(err);
    };

    out.* = owned;
    return .REGREX_OK;
} 

/// Finds all non-overlapping matches for a compiled pattern.
///
/// Stores resulting `regx_match_list_t` to `out_obj`.
/// It must be released with `regx_match_list_destroy()`.
pub export fn regx_pattern_find_all(
    pattern: ?*const regx_pattern_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_list_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    out.* = null;

    const matches = p.findAll(input) catch |err| {
        return toErrorCode(err);
    };
    const result = WrappedMatchList.create(
        c_alloc, 
        matches
    ) catch |err| {
        return toErrorCode(err);
    };

    out.* = result;
    return .REGREX_OK;
}

/// Replaces all matches found by the compiled pattern.

/// Stores a new string buffer to `out_buf` where matches
/// are replaced with `repl_buf`. Does NOT modify the original input. 
/// Controls number of replacements with `count` 
/// (`count == 0` means replacing all matches).

/// Output buffer must be released with `regx_buffer_destroy()`.
pub export fn regx_pattern_sub(
    pattern: ?*const regx_pattern_t,
    repl_buf: regx_buffer_t,
    input_buf: regx_buffer_t,
    count: usize,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };
    const repl = toOwnedSlice(repl_buf) catch |err| {
        return toErrorCode(err);
    };
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    const buf = p.sub(
        repl, 
        input, 
        .{ .count = count }
    ) catch |err| {
        return toErrorCode(err);
    };
    storeBuffer(c_alloc, buf, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Calls the lazy iterator to produce the next match.

/// Stores produced match to `out_obj`. It must be released
/// with `regx_match_destroy()`. Returns .REGX_ENOMATCH and sets
/// `out_obj` to `null` when the iterator is exhausted.
pub export fn regx_iter_next(
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

/// `regx_iter_t` destructor.
///
/// Passing `null` is valid and has no effect.
///
/// Matches already produced by the iterator are not destroyed
/// and must be released separately.
pub export fn regx_iter_destroy(iter: ?*regx_iter_t) void {
    WrappedIterator.destroy(c_alloc, iter);
}

/// Creates a borrowed buffer of the `str`
///
/// Points directly to `str` without allocating, copying or taking ownership.
/// Buffer length excludes the trailing `\0` byte.
///
/// If `str` is `null`, returns an empty buffer.
pub export fn regx_buffer_from_cstr(str: ?[*:0]const u8) regx_buffer_t {
    const s = str orelse return .{ .ptr = null, .len = 0 };

    return .{ .ptr = s, .len = std.mem.len(s) };
}

/// Releases memory held by an owned buffer.
///
/// Should only be used for `buffer` which was allocated,
/// e.g. by `regrex_sub()` or `regx_pattern_sub()`.
///
/// Passing an empty buffer or a buffer with a `null` pointer is allowed
/// and has no effect.
pub export fn regx_buffer_destroy(buffer: regx_buffer_t) void {
    const ptr = buffer.ptr orelse return;

    const mutable: [*]u8 = @constCast(ptr);
    c_alloc.free(mutable[0 .. buffer.len]);
}

/// Maps return code to a static string message.
///
/// The returned pointer has static storage duration and must not be freed.
pub export fn regrex_error(code: regx_errcode_t) [*:0]const u8 {
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

/// Compiles a regex pattern.
///
/// Stores the result to `out_obj` as a reusable pattern type
/// which does not require to be recompiled for each operation.
/// Must be released with `regx_pattern_destroy()`
pub export fn regrex_compile(
    pattern_buf: regx_buffer_t,
    out_obj: ?*?*regx_pattern_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_buf) catch |err| {
        return toErrorCode(err);
    };
    const compiled = regrex.compile(c_alloc, pattern) catch |err| {
        return toErrorCode(err);
    };
    out.* = compiled;
    return .REGREX_OK;
}

/// Compiles the string pattern and searches for the first match.
/// Compiled pattern is automatically destroyed at the end of the execution.
///
/// The returned match is stored to the `out_obj` 
/// and must be released with `regx_match_destroy()`.
///
/// Returns .REGX_ENOMATCH if no match found; 
/// `out_obj` is set to `null`
pub export fn regrex_search(
    pattern_buf: regx_buffer_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_buf) catch |err| {
        return toErrorCode(err);
    };
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    const result = regrex.search(
        c_alloc, 
        pattern, 
        input
    ) catch |err| {
        return toErrorCode(err);
    };

    storeMatch(result, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Compiles the string pattern and looks for matches
/// at the beginning of the input.
/// Compiled pattern is automatically destroyed at the end of the execution.
///
/// The returned match is stored to the `out_obj` 
/// and must be released with `regx_match_destroy()`.
///
/// Returns .REGX_ENOMATCH if no match found; 
/// `out_obj` is set to `null`
pub export fn regrex_match(
    pattern_buf: regx_buffer_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_buf) catch |err| {
        return toErrorCode(err);
    };
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    const result = regrex.match(
        c_alloc, 
        pattern, 
        input
    ) catch |err| {
        return toErrorCode(err);
    };

    storeMatch(result, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

/// Compiles the string pattern and collects all non-overlapping matches.
/// Compiled pattern is automatically destroyed at the end of the execution.
///
/// The returned match list is stored to the `out_obj` 
/// and must be released with `regx_match_list_destroy()`.
///
/// Returns .REGX_ENOMATCH if no match found; 
/// `out_obj` is set to `null`
pub export fn regrex_find_all(
    pattern_buf: regx_buffer_t,
    input_buf: regx_buffer_t,
    out_obj: ?*?*regx_match_list_t,
) regx_errcode_t {
    const out = out_obj orelse return .REGREX_EARG;
    out.* = null;

    const pattern = toOwnedSlice(pattern_buf) catch |err| {
        return toErrorCode(err);
    };
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
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

/// Compiles the string pattern and replaces all matches.
/// Compiled pattern is automatically destroyed at the end of the execution.
///
/// Stores a new string buffer to `out_buf` where matches
/// are replaced with `repl_buf`. Does NOT modify the original input. 
/// Controls number of replacements with `count` 
/// (`count == 0` means replacing all matches).
///
/// Output buffer must be released with `regx_buffer_destroy()`.
pub export fn regrex_sub(
    pattern_buf: regx_buffer_t,
    repl_buf: regx_buffer_t,
    input_buf: regx_buffer_t,
    count: usize,
    out_buf: ?*regx_buffer_t,
) regx_errcode_t {
    const out = out_buf orelse return .REGREX_EARG;
    out.* = .{
        .ptr = null,
        .len = 0,
    };
    const pattern = toOwnedSlice(pattern_buf) catch |err| {
        return toErrorCode(err);
    };
    const repl = toOwnedSlice(repl_buf) catch |err| {
        return toErrorCode(err);
    };
    const input = toOwnedSlice(input_buf) catch |err| {
        return toErrorCode(err);
    };

    const buf = regrex.sub(
        c_alloc, 
        pattern, 
        repl,
        input,
        .{ .count = count }
    ) catch |err| {
        return toErrorCode(err);
    };

    storeBuffer(c_alloc, buf, out) catch |err| {
        return toErrorCode(err);
    };
    return .REGREX_OK;
}

//====================================
// Type conversions between Zig and C
//====================================

/// Converts a C string to Zig slice.
/// 
/// Receives a structure with a pointer to a starting index of a byte buffer
/// and the number of bytes `len` to expose
/// 
/// Returns an empty slice if `len` is 0 even if `ptr` is null
/// 
/// Returns `null` if `len > 0` and `ptr` is null
/// 
/// Returns a slice that starts with 0 and ends at received string length
fn toOwnedSlice(buffer: regx_buffer_t) RegrexError![]const u8 {
    if (buffer.len == 0) return "";

    const ptr = buffer.ptr orelse {
        return RegrexError.InvalidArgument;
    };
    return ptr[0 .. buffer.len];
}

/// Converts a Zig slice to a C string.
/// 
/// Caller owns returned pointer and must release it with the same allocator 
/// and correct allocation length. The allocation length is `buffer.len + 1`
/// because `dupeSentinel` adds a trailing zero byte.
/// 
/// Returns a pointer to a newly allocated null-terminated byte buffer
/// 
/// Returns `RegrexError.InvalidArgument` if `buffer` is null
/// 
/// Returns `RegrexError.MemoryError` if allocation failed
fn toCString(
    alloc: std.mem.Allocator,
    buffer: ?[]const u8,
) RegrexError![*:0]const u8 {
    const buf = buffer orelse return RegrexError.InvalidArgument;

    const sent_buf = alloc.dupeSentinel(u8, buf, 0) catch {
        return RegrexError.MemoryError;
    };

    return sent_buf.ptr;
}

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

//=====================
// Testing suites
//=====================

fn TestBuffer(bytes: []const u8) regx_buffer_t {
    return .{
        .ptr = bytes.ptr,
        .len = bytes.len,
    };
}

fn expectEqualBuffers(expected: []const u8, buffer: regx_buffer_t) !void {
    try testing.expectEqual(expected.len, buffer.len);

    if (expected.len == 0) return;

    const ptr = buffer.ptr orelse {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings(expected, ptr[0..buffer.len]);
}

fn destroyBuffer(buffer: *regx_buffer_t) void {
    if (buffer.ptr != null) {
        regx_buffer_destroy(buffer.*);
        buffer.* = .{ .ptr = null, .len = 0 };
    }
}

test "storeBuffer() should store non-empty buffer and transfer ownership" {
    const allocator = testing.allocator;
    const buf = try allocator.dupe(u8, "kek");
    var out: regx_buffer_t = .{ .ptr = null, .len = 0 };

    storeBuffer(allocator, buf, &out) catch {
        try testing.expect(false);
        return;
    };

    try testing.expect(out.ptr != null);
    try testing.expectEqual(@as(usize, 3), out.len);
    try testing.expectEqualStrings("kek", out.ptr.?[0 .. out.len]);

    allocator.free(out.ptr.?[0 .. out.len]);
}

test "storeBuffer() should free empty buffer and store null output" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 0);
    var out: regx_buffer_t = .{ .ptr = undefined, .len = 420 };

    storeBuffer(allocator, buf, &out) catch {
        try testing.expect(false);
        return;
    };

    try testing.expect(out.ptr == null);
    try testing.expectEqual(@as(usize, 0), out.len);
}

test "storeBuffer() should return RegrexError.InvalidArgument if output buffer is null" {
    const allocator = testing.allocator;
    const buf = try allocator.alloc(u8, 0);
    defer allocator.free(buf);

    const out: ?*regx_buffer_t = null;
    try testing.expectError(
        RegrexError.InvalidArgument,
        storeBuffer(allocator, buf, out),
    );
}

test "regx_pattern_search() and regx_pattern_match() should use different match modes" {
    var pattern: ?*regx_pattern_t = null;

    try testing.expectEqual(
        .REGREX_OK,
        regrex_compile(TestBuffer("foo"), &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer regx_pattern_destroy(p);

    var search_match: ?*regx_match_t = null;
    try testing.expectEqual(
        .REGREX_OK,
        regx_pattern_search(p, TestBuffer("xxfoo"), &search_match),
    );
    if (search_match) |m| regx_match_destroy(m);

    var start_match: ?*regx_match_t = null;
    try testing.expectEqual(
        .REGREX_ENOMATCH,
        regx_pattern_match(p, TestBuffer("xxfoo"), &start_match),
    );
    try testing.expect(start_match == null);
}

test "regx_pattern_find_iter() should iterate over matches" {
    var pattern: ?*regx_pattern_t = null;

    try testing.expectEqual(
        .REGREX_OK,
        regrex_compile(TestBuffer("[a-z]+"), &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer regx_pattern_destroy(p);

    var iter: ?*regx_iter_t = null;
    try testing.expectEqual(
        .REGREX_OK,
        regx_pattern_find_iter(p, TestBuffer("one two"), &iter),
    );
    const it = iter orelse {
        try testing.expect(false);
        return;
    };
    defer regx_iter_destroy(it);

    var first: ?*regx_match_t = null;
    try testing.expectEqual(.REGREX_OK, regx_iter_next(it, &first));
    const first_match = first orelse {
        try testing.expect(false);
        return;
    };
    defer regx_match_destroy(first_match);

    var first_span: regx_group_t = undefined;
    try testing.expectEqual(.REGREX_OK, regx_match_span(first_match, 0, &first_span));
    try testing.expectEqual(@as(usize, 0), first_span.start);
    try testing.expectEqual(@as(usize, 3), first_span.end);

    var second: ?*regx_match_t = null;
    try testing.expectEqual(.REGREX_OK, regx_iter_next(it, &second));
    if (second) |m| regx_match_destroy(m);

    var end: ?*regx_match_t = null;
    try testing.expectEqual(.REGREX_ENOMATCH, regx_iter_next(it, &end));
    try testing.expect(end == null);
}

test "regx_pattern_sub() should write replacement output buffer" {
    var pattern: ?*regx_pattern_t = null;

    try testing.expectEqual(
        .REGREX_OK,
        regrex_compile(TestBuffer("[0-9]+"), &pattern),
    );
    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer regx_pattern_destroy(p);

    var out: regx_buffer_t = .{ .ptr = null, .len = 0 };
    try testing.expectEqual(
        .REGREX_OK,
        regx_pattern_sub(p, TestBuffer("#"), TestBuffer("a12b34"), 0, &out),
    );
    defer destroyBuffer(&out);

    try expectEqualBuffers("a#b#", out);
}

test "regx_buffer_from_cstr() should create a borrowed buffer from a C string" {
    const buffer = regx_buffer_from_cstr("lolkek");
    try expectEqualBuffers("lolkek", buffer);
}

test "regx_buffer_from_cstr() should return empty buffer for null input" {
    const buffer = regx_buffer_from_cstr(null);

    try testing.expect(buffer.ptr == null);
    try testing.expectEqual(@as(usize, 0), buffer.len);
}

test "regrex_error() maps return code to corresponding string message" {
    const expected = "Invalid UTF-8 byte sequence";
    const msg = regrex_error(.REGREX_EBADUTF8);
    const result = toOwnedSlice(.{
        .ptr = msg,
        .len = std.mem.len(msg),
    }) catch {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings(expected, result);
}

test "regrex_compile() should return a compiled pattern handle" {
    var pattern: ?*regx_pattern_t = null;

    const code = regrex_compile(TestBuffer("[0-9]+"), &pattern);
    try testing.expectEqual(.REGREX_OK, code);

    const p = pattern orelse {
        try testing.expect(false);
        return;
    };
    defer regx_pattern_destroy(p);
}

test "regrex_search() should return match span and captured groups" {
    var match: ?*regx_match_t = null;

    const code = regrex_search(
        TestBuffer("([a-z]+)=([0-9]+)"),
        TestBuffer("foo=123"),
        &match,
    );
    try testing.expectEqual(.REGREX_OK, code);

    const m = match orelse {
        try testing.expect(false);
        return;
    };
    defer regx_match_destroy(m);

    var groups_len: usize = 0;
    try testing.expectEqual(
        .REGREX_OK,
        regx_match_groups_len(m, &groups_len),
    );
    try testing.expectEqual(@as(usize, 2), groups_len);

    var span: regx_group_t = undefined;
    try testing.expectEqual(
        .REGREX_OK,
        regx_match_span(m, 0, &span),
    );
    try testing.expectEqual(@as(usize, 0), span.start);
    try testing.expectEqual(@as(usize, 7), span.end);

    var name: regx_buffer_t = .{ .ptr = null, .len = 0 };
    try testing.expectEqual(
        .REGREX_OK,
        regx_match_group(m, 1, &name),
    );
    defer destroyBuffer(&name);
    try expectEqualBuffers("foo", name);

    var value: regx_buffer_t = .{ .ptr = null, .len = 0 };
    try testing.expectEqual(
        .REGREX_OK,
        regx_match_group(m, 2, &value),
    );
    defer destroyBuffer(&value);
    try expectEqualBuffers("123", value);
}

test "regrex_match() should not search past the beginning" {
    var match: ?*regx_match_t = null;

    const code = regrex_match(
        TestBuffer("foo"),
        TestBuffer("xxfoo"),
        &match,
    );

    try testing.expectEqual(.REGREX_ENOMATCH, code);
    try testing.expect(match == null);
}

test "regrex_find_all() should return a match list" {
    var list: ?*regx_match_list_t = null;

    try testing.expectEqual(
        .REGREX_OK,
        regrex_find_all(TestBuffer("([0-9]+)"), TestBuffer("a1 b22"), &list),
    );

    const l = list orelse {
        try testing.expect(false);
        return;
    };
    defer regx_match_list_destroy(l);

    var len: usize = 0;
    try testing.expectEqual(.REGREX_OK, regx_match_list_len(l, &len));
    try testing.expectEqual(@as(usize, 2), len);

    var span: regx_group_t = undefined;
    try testing.expectEqual(.REGREX_OK, regx_match_list_span(l, 1, 0, &span));
    try testing.expectEqual(@as(usize, 4), span.start);
    try testing.expectEqual(@as(usize, 6), span.end);

    var group: regx_buffer_t = .{ .ptr = null, .len = 0 };
    try testing.expectEqual(.REGREX_OK, regx_match_list_group(l, 1, 1, &group));
    defer destroyBuffer(&group);
    try expectEqualBuffers("22", group);
}

test "regrex_sub() should write replacement output buffer" {
    var out: regx_buffer_t = .{ .ptr = null, .len = 0 };

    try testing.expectEqual(
        .REGREX_OK,
        regrex_sub(
            TestBuffer("[0-9]+"),
            TestBuffer("#"),
            TestBuffer("a12b34"),
            0,
            &out,
        ),
    );
    defer destroyBuffer(&out);

    try expectEqualBuffers("a#b#", out);
}

test "toOwnedSlice() should return a borrowed slice for non-null pointer" {
    const result = toOwnedSlice(.{
        .ptr = "lolkek",
        .len = 6,
    }) catch {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("lolkek", result);
}

test "toOwnedSlice() should return empty slice for zero length" {
    const result = toOwnedSlice(.{
        .ptr = @as(?[*]const u8, null),
        .len = 0,
    }) catch {
        try testing.expect(false);
        return;
    };

    try testing.expectEqualStrings("", result);
}

test "toOwnedSlice() should return RegrexError.InvalidArgument for missing non-empty pointer" {
    try testing.expectError(
        RegrexError.InvalidArgument, 
        toOwnedSlice(.{
            .ptr = @as(?[*]const u8, null),
            .len = 4,
        })
    );
}

test "toCString() should return a copied buffer with a trailing zero byte" {
    const allocator = testing.allocator;
    const input = "lolkek";

    const c_str = try toCString(allocator, input);
    defer {
        const owned: [*:0]u8 = @constCast(c_str);
        allocator.free(owned[0 .. std.mem.len(c_str) + 1]);
    }

    try testing.expectEqualStrings("lolkek", std.mem.span(c_str));
    try testing.expectEqual(@as(u8, 0), c_str[input.len]);
}

test "toCString() should return RegrexError.InvalidArgument error for null buffer" {
    const allocator = testing.allocator;

    try testing.expectError(
        RegrexError.InvalidArgument,
        toCString(allocator, @as(?[]const u8, null)),
    );
}

test "toErrorCode() maps Zig error set to corresponding return code" {
    try testing.expectEqual(
        .REGREX_EBADUTF8, 
        toErrorCode(RegrexError.InvalidUnicode),
    ); 
}
