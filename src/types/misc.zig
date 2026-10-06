const std = @import("std");
const ErrorSet = @import("./error.zig").ErrorSet;

pub const LookupOrder = enum {
    before,
    match,
    after,
};
pub const LookupFn = enum { match, search };
pub const LookupSource = enum { root, pattern };

/// C ABI memory layout compatibility flag
pub const RangeOptions = struct {
    extern_compat: bool = false,
};

pub fn formatStr(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ErrorSet![]u8 {
    return std.fmt.allocPrint(gpa, fmt, args) catch {
        return ErrorSet.MemoryError;
    };
}
