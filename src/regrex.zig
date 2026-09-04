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
    in_cstr: [*:0]const u8,
    in_buf: ?*regx_buffer_t,
    out_obj: ?*?*regx_match_t,
// convention: use actual Zig types for non-exported functions
) ext.C_ReturnCode {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const buffer = in_buf orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before finding matches
    out_obj.* = null;

    const buf_init_rc = conv.initCBufferFromSlice(
        u8,
        alloc,
        buffer,
        &idleDestructor,
        std.mem.span(in_cstr),
    );
    if (buf_init_rc != .OK) return buf_init_rc;

    const input = buffer.ptr[0..buffer.len];

    const match = switch(mode) {
        .match => p.match(input),
        .search => p.search(input),
    } catch |err| {
        return conv.toErrorCode(err);
    } orelse return .REGREX_ENOMATCH;

    out.* = ManagedMatch.init(alloc, match) catch |err| {
        match.deinit(alloc);
        return conv.toErrorCode(err);
    };
    return .OK;
}
/// Stable return code type used by the C ABI.
pub const regx_rcode_t = ext.C_ReturnCode;
pub const regx_flags_t = u8;
pub const regx_span_t = types.Span;
pub const regx_buffer_t = ext.C_GenericBuffer;

/// Initializes `buffer` with storage for `capacity` fixed-size elements
///
/// `destroy_cb` is called for each remaining element when the buffer is freed.
/// Use `ext.C_noOpDestructor` for element types that require no cleanup.
export fn regx_buffer_alloc(
    destroy_cb: *const fn(*anyopaque) callconv(.c) void,
    capacity: usize,
    item_align: usize,
    item_size: usize,
    buffer: ?*regx_buffer_t
) callconv(.c) regx_rcode_t {
    const buf = buffer orelse return .REGREX_EARG;

    if (
        item_align == 0 or
        item_size == 0 or
        !std.math.isPowerOfTwo(item_align)
    ) return .REGREX_EARG;

    return regx_buffer_t.init(
        c_alloc,
        capacity,
        destroy_cb,
        item_align,
        item_size,
        buf,
    );
}

/// Deinitializes the items within the buffer and then dereferences the buffer itself
export fn regx_buffer_free(buffer: ?*regx_buffer_t) callconv(.c) void {
    const buf = buffer orelse return;
    regx_buffer_t.deinit(c_alloc, buf);
}

export fn regx_buffer_push(buffer: ?*regx_buffer_t, item: ?*const anyopaque) callconv(.c) regx_rcode_t {
    const buf = buffer orelse return .REGREX_EARG;
    const iptr = item orelse return .REGREX_EARG;

    return regx_buffer_t.push(buf, iptr);
}

export fn regx_buffer_pop(buffer: ?*regx_buffer_t, item: ?*anyopaque) callconv(.c) regx_rcode_t {
    const buf = buffer orelse return .REGREX_EARG;
    const iptr = item orelse return .REGREX_EARG;

    return regx_buffer_t.pop(buf, iptr);
}

/// Opaque handler for result type produced by matching operations.
///
/// It is allocated on the heap and must be released.
pub const regx_match_t = opaque {};

export fn regx_match_destroy(match: ?*regx_match_t) void {
    ManagedMatch.deinit(c_alloc, match);
}

/// Returns the start and end byte offsets of a capture group in input string
export fn regx_match_span(match: ?*const regx_match_t, i: usize, out: ?*regx_span_t) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out orelse return .REGREX_EARG;
    const owned = ManagedMatch.unwrapConst(m);

    span.* = owned.span(i) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}

/// Copies the bytes matched by capture group `i` into a byte buffer
export fn regx_match_group(match: ?*const regx_match_t, i: usize, out: ?*regx_buffer_t) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buffer = out orelse return .REGREX_EARG;

    const owned = ManagedMatch.unwrapConst(m);
    const group_str = owned.group(i) catch |err| {
        return conv.toErrorCode(err);
    };

    return conv.initCBufferFromSlice(u8, c_alloc, buffer, &idleDestructor, group_str);
}

/// Copies the bytes of the full match into a byte buffer
export fn regx_match_full(match: ?*const regx_match_t, out: ?*regx_buffer_t) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buffer = out orelse return .REGREX_EARG;

    const owned = ManagedMatch.unwrapConst(m);
    const full_match = owned.group(0) catch |err| {
        return conv.toErrorCode(err);
    };

    return conv.initCBufferFromSlice(u8, c_alloc, buffer, &idleDestructor, full_match);
}

/// Copies all groups (byte offsets) except the first one into a buffer
export fn regx_match_subgroups(
    match: ?*const regx_match_t,
    out_buf: ?*regx_buffer_t
) callconv(.c) regx_rcode_t {
    const m = match orelse return .REGREX_EARG;
    const buffer = out_buf orelse return .REGREX_EARG;

    const owned = ManagedMatch.unwrapConst(m);
    const subgroups = owned.subgroups();

    return conv.initCBufferFromSlice(regx_span_t, c_alloc, buffer, &idleDestructor, subgroups);
}

/// Opaque handler for a lazy iterator created by the compiled pattern.
///
/// The parent pattern and input buffer must outlive the iterator.
///
/// It is allocated on the heap and must be released
pub const regx_iter_t = opaque {};

/// `regx_iter_t` destructor.
///
/// Passing `null` is valid and has no effect.
///
/// Matches already produced by the iterator are not destroyed
/// and must be released separately.
export fn regx_iter_destroy(iter: ?*regx_iter_t) void {
    ManagedIterator.deinit(c_alloc, iter);
}

/// Perform lookup iteration once; store result at `out_obj`.
///
/// If Match is found, it must be released. If the iterator is exhausted, stores `null`
/// at `out_obj` and returns `.REGREX_ENOMATCH`
export fn regx_iter_next(iter: ?*regx_iter_t, out_obj: ?*?*regx_match_t) regx_rcode_t {
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
    in_cstr: [*:0]const u8,
    in_buf: ?*regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    return patternMatchImpl(.match, c_alloc, pattern, in_cstr, in_buf, out_obj);
}

export fn regx_pattern_search(
    pattern: ?*const regx_pattern_t,
    in_cstr: [*:0]const u8,
    in_buf: ?*regx_buffer_t,
    out_obj: ?*?*regx_match_t,
) callconv(.c) regx_rcode_t {
    return patternMatchImpl(.search, c_alloc, pattern, in_cstr, in_buf, out_obj);
}

export fn regx_pattern_find_iter(
    pattern: ?*const regx_pattern_t,
    in_cstr: [*:0]const u8,
    in_buf: ?*regx_buffer_t,
    out_obj: ?*?*regx_iter_t,
) callconv(.c) regx_rcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const out = out_obj orelse return .REGREX_EARG;
    const buffer = in_buf orelse return .REGREX_EARG;

    // Ensure that output pointer is null if function fails before creating iterator
    out.* = null;

    const buf_init_rc = conv.initCBufferFromSlice(
        u8,
        c_alloc,
        buffer,
        &idleDestructor,
        std.mem.span(in_cstr),
    );
    if (buf_init_rc != .OK) return buf_init_rc;

    const input = buffer.ptr[0..buffer.len];
    const iter = p.findIter(input) catch |err| {
        return conv.toErrorCode(err);
    };

    out.* = ManagedIterator.init(c_alloc, iter) catch |err| {
        return conv.toErrorCode(err);
    };
    return .OK;
}
// export fn regx_pattern_find_all(
//     pattern: ?*const regx_pattern_t,
//     input: ?[*:0]const u8,
//     out_buf: ?*regx_buffer_t
// ) regx_rcode_t {
//     const p = pattern orelse return .REGREX_EARG;
//     const in = input orelse return .REGREX_EARG;
//     const out = out_buf orelse return .REGREX_EARG;
//     const size = @sizeOf(*regx_match_t);
//     const alignment = @alignOf(*regx_match_t);
//
//     out.* = .{
//         .ptr = null,
//         .isize = 0,
//         .ialign = 0,
//         .capacity = 0,
//         .head = 0,
//         .tail = 0,
//         .len = 0,
//     };
//
//     const match_list: regrex.MatchList = p.findAll(std.mem.span(in)) catch |err| {
//         return conv.toErrorCode(err);
//     };
//     defer match_list.deinit();
//
//     const matches: []regrex.Match = match_list.toOwnedSlice() catch |err| {
//         return conv.toErrorCode(err);
//     };
//     // `toOwnedSlice` transfers both Match and backing alloc. Keep track of already owned Matches
//     var owned: usize = 0;
//     defer {
//         // Matches not wrapped still must be freed
//         for(matches[owned..]) |*m| {
//             m.deinit(c_alloc);
//         }
//         // Matches have been moved or destroyed above; destroy the slice itself
//         c_alloc.free(matches);
//     }
//     // Empty matches list is valid
//     if (matches.len == 0) {
//         out.isize = size;
//         out.ialign = alignment;
//         return .OK;
//     }
//
//     const init_res = regx_buffer_init(out, matches.len, size, alignment);
//     if (init_res != .OK) return init_res;
//
//     var done = false;
//     defer {
//         if (!done) {
//             // Destroy every wrapped Match already pushed before failure
//             var wrapped: ?*regx_match_t = null;
//             while(regx_buffer_pop(out, @ptrCast(&wrapped)) == .OK) {
//                 ManagedMatch.deinit(c_alloc, wrapped);
//             }
//             regx_buffer_destroy(out);
//         }
//     }
//
//     for (matches) |match| {
//         const wrapped = ManagedMatch.init(c_alloc, match) catch |err| {
//             return conv.toErrorCode(err);
//         };
//         owned += 1;
//
//         const push_res = regx_buffer_push(out, &wrapped);
//         if (push_res != .OK) {
//             ManagedMatch.deinit(c_alloc, wrapped);
//             return .REGREX_ENOSPACE;
//         }
//     }
//     done = true;
//     return .OK;
// }
