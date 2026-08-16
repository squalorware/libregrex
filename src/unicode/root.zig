const std = @import("std");
const Error = @import("types").Error;
pub const ranges = @import("./ranges.zig");
pub const Rune = @import("./Rune.zig");

/// Decodes the Unicode Rune beginning at byte offset `pos`.
///
/// Returns `null` when `pos` points to the end of the input.
pub fn decodeAt(input: []const u8, pos: usize) Error!?Rune {
    if (pos == input.len) return null;

    if (pos >= input.len) return Error.OutOfRange;

    const len = Rune.byteLength(input[pos]) orelse return Error.InvalidUnicode;
    if (pos + len > input.len) return Error.InvalidUnicode;

    const view = std.unicode.Utf8View.init(input[pos .. pos + len]) catch {
        return Error.InvalidUnicode;
    };
    var iter = view.iterator();

    const scalar = iter.nextCodepoint() orelse return Error.InvalidUnicode;

    return Rune.from(scalar);
}

/// Decodes the Unicode Rune ending immediately before byte offset `pos`.
///
/// Returns `null` when `pos == 0`.
///
/// Returns `Error.InvalidUnicode` if `pos` does not lie on a valid UTF-8
pub fn decodePrev(input: []const u8, pos: usize) Error!?Rune {
    if (pos == 0) return null;
    if (pos > input.len) return Error.OutOfRange;

    // Start at the byte right before input[pos]
    var start: usize = pos - 1;
    // Iterate backwards until reaching the leading byte of the Unicode sequence
    while (start > 0 and (input[start] & 0xC0) == 0x80) {
        start -= 1;
    }

    const rune = try decodeAt(input, start) orelse {
        return Error.InvalidUnicode;
    };

    if (start + rune.len != pos) return Error.InvalidUnicode;

    return rune;
}

/// Advances `pos` by one complete decoded Unicode Rune.
///
/// Returns `false` if the input has been exhausted.
pub fn nextPos(input: []const u8, pos: *usize) Error!bool {
    const rune = try decodeAt(input, pos.*) orelse return false;
    pos.* += rune.len;
    return true;
}

test {
    _ = @import("./ranges.zig");
    _ = @import("./Rune.zig");
}
