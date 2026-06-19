//! Various utility functions and snippets, mostly for dealing with UTF-8.
//! 
//! Regrex stores strings as UTF-8 byte slices, but performs matching
//! against Unicode scalar values. Helpers below allow decoding one code point
//! at a given byte position and advancing byte offsets safely
const std = @import("std");
const Error = @import("errors.zig").RegrexError;
const types = @import("types.zig");

/// Decodes a UTF-8 code point from `input` string at byte offset `pos`
/// 
/// Returns `null` if `pos` is at or past the end of input
/// 
/// Returns `Error.InvalidUnicode` if `pos` points to a broken UTF-8 value 
/// (invalid leading byte, truncated) or to a sequence that cannot be decoded
/// 
/// Returns `DecodedRune` containing a Unicode scalar value and its byte length otherwise
pub fn decodeRuneAt(input: []const u8, pos: usize) Error!?types.DecodedRune {
    if (pos >= input.len) return null;

    const len = std.unicode.utf8ByteSequenceLength(input[pos]) catch {
        return Error.InvalidUnicode;
    };

    if (pos + len > input.len) return Error.InvalidUnicode;

    const rune = std.unicode.utf8Decode(input[pos .. pos + len]) catch {
        return Error.InvalidUnicode;
    };

    return .{
        .rune = rune,
        .len = len,
    };
}

/// Advances byte offset `pos` into `input` by one UTF-8 code point.
/// 
/// Returns `true` if `Rune` was decoded 
/// and `pos` was advanced by its byte length
/// 
/// Returns `false` if `pos` is already at or past the end of `input`.
/// In this case `pos` is not changed.
/// 
/// Returns `Error.InvalidUnicode` if the byte sequence 
/// at `pos` is not valid UTF-8
pub fn advanceOneRune(input: []const u8, pos: *usize) Error!bool {
    const decoded = try decodeRuneAt(input, pos.*) orelse return false;
    pos.* += decoded.len;
    return true;
}

test "Should receive null from `decodeRuneAt` when position is at or past end" {
    const input = "abc";

    try std.testing.expectEqual(@as(?types.DecodedRune, null), try decodeRuneAt(input, input.len));
    try std.testing.expectEqual(@as(?types.DecodedRune, null), try decodeRuneAt(input, input.len + 1));
}

test "Should successfully decode when ASCII rune passed to decodeRuneAt" {
    const input = "abc";
    const decoded = (try decodeRuneAt(input, 0)).?;

    try std.testing.expectEqual(@as(types.Rune, 'a'), decoded.rune);
    try std.testing.expectEqual(@as(usize, 1), decoded.len);
}

test "Should successfully decode when Cyrillic rune passed to decodeRuneAt" {
    const input = "ґєї";
    const decoded = (try decodeRuneAt(input, 0)).?;

    try std.testing.expectEqual(@as(types.Rune, 'ґ'), decoded.rune);
    try std.testing.expectEqual(@as(usize, 2), decoded.len);
}

test "Should successfully decode when mixed at byte offsets UTF-8 input passed to decodeRuneAt" {
    const input = "hうй";

    const first = (try decodeRuneAt(input, 0)).?;
    try std.testing.expectEqual(@as(types.Rune, 'h'), first.rune);
    try std.testing.expectEqual(@as(usize, 1), first.len);

    const second = (try decodeRuneAt(input, 1)).?;
    try std.testing.expectEqual(@as(types.Rune, 'う'), second.rune);
    try std.testing.expectEqual(@as(usize, 3), second.len);

    const third = (try decodeRuneAt(input, 4)).?;
    try std.testing.expectEqual(@as(types.Rune, 'й'), third.rune);
    try std.testing.expectEqual(@as(usize, 2), third.len);
}

test "Should return Error.InvalidUnicode from decodeRuneAt for invalid leading byte" {
    const input = [_]u8{0x80};

    try std.testing.expectError(
        Error.InvalidUnicode,
        decodeRuneAt(input[0..], 0),
    );
}

test "Should return Error.InvalidUnicode from decodeRuneAt for truncated UTF-8 sequence" {
    const input = [_]u8{0xD0};

    try std.testing.expectError(
        Error.InvalidUnicode,
        decodeRuneAt(input[0..], 0),
    );
}

test "Should advance `pos` by one ASCII byte when passed to advanceOneRune" {
    const input = "abc";
    var pos: usize = 0;

    try std.testing.expectEqual(true, try advanceOneRune(input, &pos));
    try std.testing.expectEqual(@as(usize, 1), pos);
}

test "Should advance `pos` by UTF-8 byte length when passed to advanceOneRune" {
    const input = "hうй";
    var pos: usize = 0;

    try std.testing.expectEqual(true, try advanceOneRune(input, &pos));
    try std.testing.expectEqual(@as(usize, 1), pos);

    try std.testing.expectEqual(true, try advanceOneRune(input, &pos));
    try std.testing.expectEqual(@as(usize, 4), pos);
}

test "Should return false at end without changing position from advanceOneRune" {
    const input = "abc";
    var pos: usize = input.len;

    try std.testing.expectEqual(false, try advanceOneRune(input, &pos));
    try std.testing.expectEqual(@as(usize, input.len), pos);
}

test "Should propagate Error.InvalidUnicode by advanceOneRune" {
    const input = [_]u8{0x80};
    var pos: usize = 0;

    try std.testing.expectError(
        Error.InvalidUnicode,
        advanceOneRune(input[0..], &pos)
    );
    try std.testing.expectEqual(@as(usize, 0), pos);
}