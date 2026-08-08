const std = @import("std");
const RegrexError = @import("./error.zig").Error;
const matching = @import("./matching.zig");
const Match = matching.Match;
const Span = matching.Span;

/// Creates a `Match` instance from capture slots.
/// 
/// Allocates `subgroups` list on the heap to store the capture groups
/// and fills it with sentinel (`Group.none()`, no match) values, 
/// which are later replaced with actual capture groups from slots.
/// 
/// `captures_len` is a number of capture groups acquired during parsing.
/// 
/// Returns a `Match` instance with heap-allocated `subgroups` array on success:
/// - `subgroups[0]` contains the byte offset of a full match;
/// - `subgroups[1..]` contains the captured groups.
/// 
/// Returns `Error.MemoryError` if failed to allocate `subgroups` buffer
pub fn toMatch(
    allocator: std.mem.Allocator,
    input: []const u8,
    captures_len: usize,
    slots: []const ?usize,
) RegrexError!Match {
    const full_start = slots[0] orelse 0;
    const full_end = slots[1] orelse full_start;
    const groups_len = captures_len + 1;

    if (groups_len > matching.MAX_GROUPS_LEN) {
        return RegrexError.GroupBufferOverflow;
    }

    var groups_buf = allocator.alloc(Span, groups_len) catch {
        return RegrexError.MemoryError;
    };
    errdefer allocator.free(groups_buf);

    groups_buf[0] = .{
        .start = full_start,
        .end = full_end,
    };
    // Fill buffer with sentinel (no-match) groups
    @memset(groups_buf[1..], Span.none());

    var subgroup_idx: usize = 1;
    while (subgroup_idx < groups_len) : (subgroup_idx += 1) {
        const start_slot = subgroup_idx * 2;
        const end_slot = start_slot + 1;

        const group_start = slots[start_slot] orelse continue;
        const group_end = slots[end_slot] orelse continue;

        groups_buf[subgroup_idx] = .{
            .start = group_start,
            .end = group_end,
        };
    }
    return .{
        .input = input,
        .groups = groups_buf,
    };
}
