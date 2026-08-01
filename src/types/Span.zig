const std = @import("std");
const Sentinel = std.math.maxInt(usize);

/// Holds starting and ending indices of a byte range inside a string
///
/// Follows slice semantics - `start` is inclusive, `end` is exclusive
pub const Self = @This();

start: usize,
end: usize,

/// Creates a span where start and end are set to sentinel values
///
/// Used when a capture group did not participate in the match.
///
/// Sentinel values are explicitly out of range for any possible string
pub fn none() Self {
    return .{
        .start = Sentinel,
        .end = Sentinel,
    };
}

/// Checks if this span is empty (represents no match)
pub fn isNone(self: Self) bool {
    return self.start == Sentinel and self.end == Sentinel;
}
