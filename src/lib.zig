//! Namespacing for the export module
//!
//! MUST NOT be importable or accessible from the root module to avoid mixing up with the public API definitions;
//! Best is to keep using it only inside `regrex.zig`
const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const root = @import("./root.zig");
const LookupFn = types.misc.LookupFn;
const LookupSource = types.misc.LookupSource;
const T_MergedStruct = types.meta.T_MergedStruct;

/// Memory management helpers for Zig and C
pub const mem = struct {
    pub const freeAlloc = types.meta.freeAlloc;
    pub const freeMatchCallback = types.freeMatchCallback;

    /// Converts a C array to a Zig slice and releases it together with its items
    pub fn freeRaw(
        comptime T: type,
        alloc: std.mem.Allocator,
        ptr: ?[*]T,
        len: usize,
        destroy_cb: ?types.meta.T_DestructorCallback(T),
    ) void {
        const buf: [*]T = ptr orelse return;

        _ = freeAlloc(T, alloc, buf[0..len], destroy_cb);
    }
};

/// Type casting between Zig and C
pub const cast = struct {
    pub const toCString = types.conv.toC_String;
    pub const toReturnCode = types.conv.toErrorCode;
    pub const toErrorMsg = types.conv.toErrorMsg;
    pub const toZigError = types.conv.toErrorSet;
};

/// C-compatible types
pub const ctypes = struct {
    /// Corresponds to `const char*` in C
    pub const ConstStr = [*:0]const u8;
    pub const Rcode = types.conv.ReturnCode;
    /// Corresponds to `char*` in C
    pub const Str = [*:0]u8;
};

pub const helpers = struct {
    /// Creates a proxy interface between an external opaque and an internal struct
    pub const initOpaqueInterface = types.meta.T_OpaqueInterface;

    /// Allows common interface between calling `Pattern.match`/`Pattern.search` and root `match`/`search`
    pub fn commonMatchImpl(
        comptime Fn: LookupFn,
        comptime M: LookupSource,
        alloc: std.mem.Allocator,
        subject: anytype,
        in_str: ?ctypes.ConstStr,
    ) RegrexError!RegrexMatch {
        const input: ctypes.ConstStr = in_str orelse return RegrexError.InvalidArgument;

        const m: RegrexMatch = if (comptime M == .pattern) blk: {
            const pattern: *RegrexPattern = subject orelse return RegrexError.InvalidArgument;

            break :blk try switch (Fn) {
                .match => pattern.match(std.mem.span(input)),
                .search => pattern.search(std.mem.span(input)),
            } orelse return RegrexError.NoMatch;
        } else blk: {
            const pattern: ctypes.ConstStr = subject.pattern orelse return RegrexError.InvalidArgument;

            break :blk try switch (Fn) {
                .match => regrexMatch(alloc, std.mem.span(pattern), std.mem.span(input), subject.flags),
                .search => regrexSearch(alloc, std.mem.span(pattern), std.mem.span(input), subject.flags),
            } orelse return RegrexError.NoMatch;
        };

        return m;
    }
};

pub const RegrexError = types.errors.ErrorSet;
pub const RegrexFlags = engine.Flags;
pub const RegrexIterator = engine.LazyIterator;
pub const RegrexMatch = types.Match;
pub const RegrexPattern = engine.Pattern;
pub const RegrexSpan = types.Span;
pub const regrexCompile = root.compile;
pub const regrexFindAll = root.findAll;
pub const regrexMatch = root.match;
pub const regrexSearch = root.match;
pub const regrexSub = root.sub;
pub const SubOptions = T_MergedStruct(RegrexFlags, engine.PatternSubOptions);
