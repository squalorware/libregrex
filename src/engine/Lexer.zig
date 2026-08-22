//! Regular expression lexical analyzer.
//!
//! Converts a UTF-8 regex pattern into a flat `Token` stream.
//! The lexer decodes the input pattern as Unicode code points (`Rune`)
//! so that literals like Cyrillic or Chinese characters are emitted
//! as single `CHAR` tokens rather than raw UTF-8 bytes
const std = @import("std");
const types = @import("types");
const RegrexError = types.Error;
const conv = types.conv;
const Rune = @import("unicode").Rune;
const tokens = @import("./tokens.zig");
const testing = std.testing;
const Token = tokens.Token;
const TokenType = tokens.TokenType;
const TokenListBuffer = tokens.TokenListBuffer;
const mapRuneToTokenType = tokens.mapRuneToTokenType;

/// Stateful lexical analyzer and tokenizer
pub const Lexer = @This();

/// String pattern buffer (borrowed)
pattern: []const u8,
/// Current code point (`Rune`) offset
pos: usize = 0,

/// Creates a lexer over a borrowed UTF-8 pattern buffer.
pub fn init(pattern: []const u8) Lexer {
    return .{
        .pattern = pattern,
        .pos = 0,
    };
}

pub fn isSemanticEscape(char: u21) bool {
    return switch(char) {
        'd', 'D',
        'w', 'W',
        's', 'S',
        'A', 'Z',
        'b', 'B' => true,
        else => false,
    };
}
/// Transforms pattern into an owned slice of `Token`s.
///
/// If `Rune` in pattern is a metacharacter, emits a correspondent `TokenType`.
/// Literals are emitted as `CHAR` or `ESCAPED_CHAR` if escaped.
///
/// The returned slice is allocated by `alloc` and must be freed by the caller,
/// e.g. `alloc.free(tokens)`.
///
/// Returns
/// - `RegrexError.InvalidUnicode` if Rune contains an invalid UTF-8 code point
/// - `RegrexError.MemoryError` if failed allocating or manipulating dynamic Token buffer
/// - `RegrexError.TrailingEscape` if pattern ends after backslash.
pub fn tokenize(self: *Lexer, tlist: *TokenListBuffer) RegrexError!void {
    const view = std.unicode.Utf8View.init(self.pattern) catch {
        return RegrexError.InvalidUnicode;
    };
    var iter = view.iterator();

    while (iter.nextCodepoint()) |char| {
        const current_pos = self.pos;
        self.pos += 1;
    
        if (char == '\\') {
            const escaped = iter.nextCodepoint() orelse {
                return RegrexError.TrailingEscape;
            };

            self.pos += 1;

            const literal: u21 = switch(escaped) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                // Process a hexadecimal digit
                'x' => blk: {
                    const high_char = iter.nextCodepoint() orelse {
                        return RegrexError.InvalidEscape;
                    };
                    const low_char = iter.nextCodepoint() orelse {
                        return RegrexError.InvalidEscape;
                    };
                    self.pos += 2;

                    const high = conv.toHexDigit(high_char) orelse {
                        return RegrexError.InvalidEscape;
                    };
                    const low = conv.toHexDigit(low_char) orelse {
                        return RegrexError.InvalidEscape;
                    };

                    break :blk high * 16 + low;
                },
                // Process an octal digit
                '0'...'7' => blk: {
                    const second_char = iter.nextCodepoint() orelse {
                        return RegrexError.InvalidEscape;
                    };
                    const third_char = iter.nextCodepoint() orelse {
                        return RegrexError.InvalidEscape;
                    };

                    self.pos += 2;

                    const first = conv.toOctDigit(escaped).?;
                    const second = conv.toOctDigit(second_char) orelse {
                        return RegrexError.InvalidEscape;
                    };
                    const third = conv.toOctDigit(third_char) orelse {
                        return RegrexError.InvalidEscape;
                    };

                    break :blk first * 64 + second * 8 + third;
                },
                else => escaped,
            };

            try tlist.append(.{ 
                .typ = if (isSemanticEscape(escaped)) .ESCAPED_CHAR else .CHAR,
                .val = try Rune.from(literal),
                .pos = current_pos, 
            });
            continue;
        }
        // if `null` - it's a regular literal
        const rune = try Rune.from(char);
        const typ = mapRuneToTokenType(rune) orelse .CHAR;

        try tlist.append(.{ 
            .typ = typ, 
            .val = try Rune.from(char), 
            .pos = current_pos, 
        });
    }
    try tlist.append(.{ 
        .typ = .EOF, 
        .val = null, 
        .pos = self.pos, 
    });
}

test "Should break up a pattern into a valid token stream" {
    const allocator = testing.allocator;

    var token_buffer = try tokens.TokenListBuffer.init(allocator, null);
    defer token_buffer.deinit();

    var lexer = Lexer.init("a\\.b*c");
    try lexer.tokenize(&token_buffer);

    const expected = [_]Token{
        .{ .typ = .CHAR, .val = try Rune.from('a'), .pos = 0 },
        .{ .typ = .CHAR, .val = try Rune.from('.'), .pos = 1 },
        .{ .typ = .CHAR, .val = try Rune.from('b'), .pos = 3 },
        .{ .typ = .STAR, .val = try Rune.from('*'), .pos = 4 },
        .{ .typ = .CHAR, .val = try Rune.from('c'), .pos = 5 },
        .{ .typ = .EOF, .val = null, .pos = 6 },
    };

    for (token_buffer.items(), 0..) |token, i| {
        try testing.expectEqual(expected[i].typ, token.typ);
        try testing.expectEqual(expected[i].val, token.val);
        try testing.expectEqual(expected[i].pos, token.pos);
    }
}
