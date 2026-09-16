//! Common namespace for various types and functions
//! which are used to implement the exported C compatibility layer
//!
//! MUST NOT be importable or accessible from the root module
//! to avoid mixing up with the public API definitions;
//! When imported, MUST NOT be public
const std = @import("std");
const types = @import("types");
const engine = @import("engine");
const root = @import("./root.zig");
const T_MergedStruct = types.meta.T_MergedStruct;

pub const C = struct {
    pub const freeBuffer = types.ext.c_freeBuffer;
    pub const Match = types.ext.C_Match;
    pub const ReturnCode = types.ext.C_ReturnCode;
    pub const StaticString = types.ext.C_StaticString;
    pub const String = types.ext.C_String;
    pub const toArray = types.conv.toC_Array;
    pub const toString = types.conv.toC_String;
    pub const toErrorMsg = types.conv.toErrorMsg;
    pub const toErrorSet = types.conv.toErrorSet;
    pub fn freeCMatchCallback(allocator: std.mem.Allocator, ptr: *types.ext.C_Match) void {
        _ = ptr.destroy(allocator);
    }
};

pub const freeAny = types.meta.freeAny;
pub const freeMatchCallback = types.freeMatchCallback;
// Allows common interface between calling `Pattern.match`/`Pattern.search` and root `match`/`search`
pub const LookupCtx = struct {
    pattern: ?C.StaticString,
    flags: u8,
};
pub const LookupFn = enum { match, search };
pub const LookupSource = enum { root, pattern };
pub const RegrexError = types.errors.ErrorSet;
pub const RegrexFlags = types.CompileFlags;
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
pub const toCompileFlags = types.conv.toCompileFlags;
pub const toErrorCode = types.conv.toErrorCode;

pub fn commonMatchImpl(
    comptime Fn: LookupFn,
    comptime M: LookupSource,
    alloc: std.mem.Allocator,
    subject: anytype,
    in_str: ?C.StaticString,
    out_obj: ?*C.Match,
) RegrexError!void {
    const input = in_str orelse return RegrexError.InvalidArgument;
    const out = out_obj orelse return RegrexError.InvalidArgument;

    const m = if (comptime M == .pattern) blk: {
        const pattern: *RegrexPattern = subject orelse return RegrexError.InvalidArgument;

        break :blk try switch (Fn) {
            .match => pattern.match(std.mem.span(input)),
            .search => pattern.search(std.mem.span(input)),
        } orelse return RegrexError.NoMatch;
    } else blk: {
        const pattern: C.StaticString = subject.pattern orelse return RegrexError.InvalidArgument;

        break :blk try switch (Fn) {
            .match => regrexMatch(alloc, std.mem.span(pattern), std.mem.span(input), toCompileFlags(subject.flags)),
            .search => regrexSearch(alloc, std.mem.span(pattern), std.mem.span(input), toCompileFlags(subject.flags)),
        } orelse return RegrexError.NoMatch;
    };

    out.* = try C.Match.create(alloc, m);
}
