const testing = @import("std").testing;
const managed = @import("./managed.zig");
const matching = @import("./matching.zig");

pub const conv = @import("./conv.zig");
pub const Error = @import("./error.zig").Error;
pub const opt_args = @import("./opt_args.zig");
pub const ManagedDynamicBuffer = managed.ManagedDynamicBuffer;
pub const ManagedOpaqueWrapper = managed.ManagedOpaqueWrapper;
pub const Match = matching.Match;
pub const MatchListBuffer = matching.MatchListBuffer;
pub const Span = matching.Span;
pub const DynamicStringBuffer = managed.ManagedDynamicBuffer(u8, null);

/// Pattern behaviour modifiers
pub const RegrexFlags = packed struct(u8) {
    /// Case-insensitive matching
    ignore_case: bool = false,
    /// Interpret `^` and `$` as marking start and end
    /// of a single line instead of the whole input
    multiline: bool = false,
    /// Wildcards match newline characters as well
    dot_all: bool = false,
    _padding: u5 = 0,
};

test {
    _ = @import("./matching.zig");
    _ = @import("./managed.zig");
    _ = @import("./conv.zig");
}
