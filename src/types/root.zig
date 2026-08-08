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

test {
    _ = @import("./matching.zig");
    _ = @import("./managed.zig");
    _ = @import("./conv.zig");
}
