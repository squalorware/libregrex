const std = @import("std");
const regrex = @import("regrex");
const types = @import("types");
const conv = types.conv;
const ext = types.ext;
const ManagedOpaqueWrapper = types.ManagedOpaqueWrapper;
const RegrexError = types.errors.ErrorSet;

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

/// Stable return code type used by the C ABI.
pub const regx_errcode_t = ext.ReturnCode;

/// Generic buffer type. Points to raw memory
pub const regx_buffer_t = extern struct {
    ptr: ?*anyopaque,
    item_size: usize,
    item_align: usize,
    capacity: usize,
    head: usize,
    tail: usize,
    len: usize,
};

export fn regx_buffer_destroy(buf: *regx_buffer_t) void {
    if (buf.ptr) |ptr| {
        const size = buf.capacity * buf.item_size;
        const alignment = std.mem.Alignment.fromByteUnits(buf.item_align);
        const base: [*]u8 = @ptrCast(ptr);

        c_alloc.rawFree(base[0..size], alignment, @returnAddress());
    }
    buf.* = .{
        .ptr = null,
        .item_size = 0,
        .item_align = 0,
        .capacity = 0,
        .head = 0,
        .tail = 0,
        .len = 0,
    };
}

export fn regx_buffer_init(
    buf: *regx_buffer_t,
    capacity: usize,
    item_size: usize,
    item_align: usize
) regx_errcode_t {
    if (item_size == 0 or item_align == 0 or !std.math.isPowerOfTwo(item_align)) {
        return .ERR;
    }
    const size = std.math.mul(usize, capacity, item_size) catch {
        return .ERR;
    };
    const alignment = std.mem.Alignment.fromByteUnits(item_align);

    const ptr = c_alloc.rawAlloc(size, alignment, @returnAddress()) orelse {
        return .ERR;
    };
    buf.* = .{
        .ptr = ptr,
        .item_size = item_size,
        .item_align = item_align,
        .capacity = capacity,
        .head = 0,
        .tail = 0,
        .len = 0,
    };
    return .OK;
}

export fn regx_buffer_push(buf: *regx_buffer_t, item: *const anyopaque) regx_errcode_t {
    if (buf.len == buf.capacity) return .ERR;

    const ptr = buf.ptr orelse return .ERR;
    const base: [*]u8 = @ptrCast(ptr);
    const offset = buf.tail * buf.item_size;
    const src: [*]const u8 = @ptrCast(item);

    @memcpy(base[offset..offset + buf.item_size], src[0..buf.item_size]);

    buf.tail = (buf.tail + 1) % buf.capacity;
    buf.len += 1;

    return .OK;
}

export fn regx_buffer_pop(buf: *regx_buffer_t, out_item: *anyopaque) regx_errcode_t {
    if (buf.len == 0) return .ERR;

    const ptr = buf.ptr orelse return .ERR;
    const base: [*]u8 = @ptrCast(ptr);
    const offset = buf.head * buf.item_size;
    const dest: [*]u8 = @ptrCast(out_item);

    @memcpy(dest[0..buf.item_size], base[offset..offset + buf.item_size]);

    buf.head = (buf.head + 1) % buf.capacity;
    buf.len -= 1;

    return .OK;
}

pub const regx_span_t = ext.ExtSpan;

/// Opaque handler for result type produced by matching operations.
///
/// It is allocated on the heap and must be released.
pub const regx_match_t = opaque {};

export fn regx_match_destroy(match: ?*regx_match_t) void {
    ManagedMatch.deinit(c_alloc, match);
}

/// Returns the start and end byte offsets of a capture group in input string
export fn regx_match_span(match: ?*const regx_match_t, i: usize, out: ?*regx_span_t) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const span = out orelse return .REGREX_EARG;
    const owned = ManagedMatch.unwrapConst(m);

    const result = owned.span(i) catch |err| {
        return conv.toErrorCode(err);
    };
    span.* = conv.toExtSpan(result);
    return .OK;
}

/// Returns character sequence delimited by start and end indices of a capture group
export fn regx_match_group(match: ?*const regx_match_t, i: usize, out: ?*?[*:0]u8) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const str = out orelse return .REGREX_EARG;

    str.* = null;
    const owned = ManagedMatch.unwrapConst(m);

    const result = owned.group(i) catch |err| {
        return conv.toErrorCode(err);
    };
    const out_str = c_alloc.dupeZ(u8, result) catch {
        return .REGREX_ENOSPACE;
    };

    str.* = out_str.ptr;
    return .OK;
}

/// Returns the string representation of the full match
export fn regx_match_full(match: ?*const regx_match_t, out: ?*?[*:0]u8) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const str = out orelse return .REGREX_EARG;

    str.* = null;
    const owned = ManagedMatch.unwrapConst(m);

    const result = owned.group(0) catch |err| {
        return conv.toErrorCode(err);
    };
    const out_str = c_alloc.dupeZ(u8, result) catch {
        return .REGREX_ENOSPACE;
    };
    str.* = out_str.ptr;

    return .OK;
}

/// Returns all groups (`[]regx_span_t { .start, .end }`)
/// except the first (`group(0)`) which represents full match
export fn regx_match_subgroups(
    match: ?*const regx_match_t,
    out_buf: ?*regx_buffer_t
) regx_errcode_t {
    const m = match orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const size = @sizeOf(regx_span_t);
    const alignment = @alignOf(regx_span_t);
    // Initialize the buffer to hold our Spans
    out.* = .{
        .ptr = null,
        .item_size = 0,
        .item_align = 0,
        .capacity = 0,
        .head = 0,
        .tail = 0,
        .len = 0,
    };

    const owned = ManagedMatch.unwrapConst(m);
    const spans = owned.subgroups();

    // An empty Span array is a valid result and requires no allocation.
    if (spans.len == 0) {
        out.item_size = size;
        out.item_align = alignment;

        return .OK;
    }

    const init_res = regx_buffer_init(out, spans.len, size, alignment);
    if (init_res != .OK) return init_res;

    for (spans) |s| {
        const span: regx_span_t = conv.toExtSpan(s);
        const push_res = regx_buffer_push(out, @ptrCast(span));

        if (push_res != .OK) {
            regx_buffer_destroy(out);
            return push_res;
        }
    }
    return .OK;
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
export fn regx_iter_next(iter: ?*regx_iter_t, out_obj: ?*?*regx_match_t) regx_errcode_t {
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

export fn regx_pattern_find_all(
    pattern: ?*const regx_pattern_t,
    input: ?[*:0]const u8,
    out_buf: ?*regx_buffer_t
) regx_errcode_t {
    const p = pattern orelse return .REGREX_EARG;
    const in = input orelse return .REGREX_EARG;
    const out = out_buf orelse return .REGREX_EARG;
    const size = @sizeOf(*regx_match_t);
    const alignment = @alignOf(*regx_match_t);

    out.* = .{
        .ptr = null,
        .item_size = 0,
        .item_align = 0,
        .capacity = 0,
        .head = 0,
        .tail = 0,
        .len = 0,
    };

    const match_list: regrex.MatchList = p.findAll(std.mem.span(in)) catch |err| {
        return conv.toErrorCode(err);
    };
    defer match_list.deinit();

    const matches: []regrex.Match = match_list.toOwnedSlice() catch |err| {
        return conv.toErrorCode(err);
    };
    // `toOwnedSlice` transfers both Match and backing alloc. Keep track of already owned Matches
    var owned: usize = 0;
    defer {
        // Matches not wrapped still must be freed
        for(matches[owned..]) |*m| {
            m.deinit(c_alloc);
        }
        // Matches have been moved or destroyed above; destroy the slice itself
        c_alloc.free(matches);
    }
    // Empty matches list is valid
    if (matches.len == 0) {
        out.item_size = size;
        out.item_align = alignment;
        return .OK;
    }

    const init_res = regx_buffer_init(out, matches.len, size, alignment);
    if (init_res != .OK) return init_res;

    var done = false;
    defer {
        if (!done) {
            // Destroy every wrapped Match already pushed before failure
            var wrapped: ?*regx_match_t = null;
            while(regx_buffer_pop(out, @ptrCast(&wrapped)) == .OK) {
                ManagedMatch.deinit(c_alloc, wrapped);
            }
            regx_buffer_destroy(out);
        }
    }

    for (matches) |match| {
        const wrapped = ManagedMatch.init(c_alloc, match) catch |err| {
            return conv.toErrorCode(err);
        };
        owned += 1;

        const push_res = regx_buffer_push(out, &wrapped);
        if (push_res != .OK) {
            ManagedMatch.deinit(c_alloc, wrapped);
            return .REGREX_ENOSPACE;
        }
    }
    done = true;
    return .OK;
}
