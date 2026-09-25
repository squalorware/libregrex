const std = @import("std");
const types = @import("types");
const conv = types.conv;
const ErrorSet = types.errors.ErrorSet;

/// Filter semantic escapes which should not be treated as literals
pub fn isReserved(char: u21) bool {
    return switch (char) {
        'd', 'D', 'w', 'W', 's', 'S', 'A', 'Z', 'b', 'B' => true,
        else => false,
    };
}

pub fn normalize(iter: *std.unicode.Utf8Iterator, char: u21, pos: *usize) ErrorSet!u21 {
    return switch (char) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        // Process a hexadecimal digit
        'x' => blk: {
            const high_char = iter.nextCodepoint() orelse {
                return ErrorSet.InvalidEscape;
            };
            const low_char = iter.nextCodepoint() orelse {
                return ErrorSet.InvalidEscape;
            };
            pos.* += 2;

            const high = conv.toHexDigit(high_char) orelse {
                return ErrorSet.InvalidEscape;
            };
            const low = conv.toHexDigit(low_char) orelse {
                return ErrorSet.InvalidEscape;
            };

            break :blk high * 16 + low;
        },
        // Process an octal digit
        '0'...'7' => blk: {
            const second_char = iter.nextCodepoint() orelse {
                return ErrorSet.InvalidEscape;
            };
            const third_char = iter.nextCodepoint() orelse {
                return ErrorSet.InvalidEscape;
            };
            pos.* += 2;

            const first = conv.toOctDigit(char).?;
            const second = conv.toOctDigit(second_char) orelse {
                return ErrorSet.InvalidEscape;
            };
            const third = conv.toOctDigit(third_char) orelse {
                return ErrorSet.InvalidEscape;
            };

            break :blk first * 64 + second * 8 + third;
        },
        else => char,
    };
}
