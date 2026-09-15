const testing = @import("std").testing;
const matching = @import("./matching.zig");
pub const conv = @import("./conv.zig");
pub const ext = @import("./ext.zig");
pub const meta = @import("./meta.zig");
pub const misc = @import("./misc.zig");
pub const errors = @import("./error.zig");
pub const CompileFlags = misc.CompileFlags;
pub const freeMatchCallback = matching.freeMatchCallback;
pub const T_ManagedArrayList = meta.T_ManagedArrayList;
pub const Match = matching.Match;
pub const MatchListBuffer = matching.MatchListBuffer;
pub const Span = matching.Span;
pub const StringBuffer = T_ManagedArrayList(u8, null);

test {
    _ = @import("./conv.zig");
    _ = @import("./matching.zig");
    _ = @import("./meta.zig");
}
