//! Regular expression lexical analyzer.
//! 
//! Converts a UTF-8 regex pattern into a flat `Token` stream.
//! The lexer decodes the input pattern as Unicode code points (`Rune`)
//! so that literals like Cyrillic or Chinese characters are emitted 
//! as single `CHAR` tokens rather than raw UTF-8 bytes
const std = @import("std");
const Error = @import("../common/errors.zig").Error;
const Rune = @import("../common/types.zig").Rune;
const Token = @import("./Token.zig");
const TokenType = Token.TokenType;
const mapRuneToTokenType = Token.mapRuneToTokenType;

/// Stateful lexical analyzer and tokenizer
pub const Self = @This();

/// String pattern buffer (borrowed)
pattern: []const u8,
/// Current code point (`Rune`) offset
pos: usize = 0,

/// Creates a lexer over a borrowed UTF-8 pattern buffer.
pub fn init(pattern: []const u8) Self {
    return .{
        .pattern = pattern,
        .pos = 0,
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
/// Returns `Error.TrailingEscape` if pattern ends after backslash.
pub fn tokenize(self: *Self, alloc: std.mem.Allocator) ![]Token {
    var list: std.ArrayList(Token) = .empty;
    defer list.deinit(alloc);
    const view = try std.unicode.Utf8View.init(self.pattern);
    var iter = view.iterator();

    while (iter.nextCodepoint()) |rune| {
        const current_pos = self.pos;
        self.pos += 1;
    
        if (rune == '\\') {
            const escaped = iter.nextCodepoint() orelse {
                return Error.TrailingEscape;
            };

            self.pos += 1;
            // Next Rune after backslash is emitted as literal
            // even if is one of metacharacters
            try list.append(alloc, .{ 
                .typ = .ESCAPED_CHAR, 
                .val = escaped, 
                .pos = current_pos, 
            });
            continue;
        }
        // if `null` - it's a regular literal
        const typ = mapRuneToTokenType(rune) orelse .CHAR;

        try list.append(alloc, .{ 
            .typ = typ, 
            .val = rune, 
            .pos = current_pos,
        });
    }
    try list.append(alloc, .{ 
        .typ = .EOF,
        .val = null,
        .pos = self.pos, 
    });

    return try list.toOwnedSlice(alloc);
}

const testing = std.testing;

test "Should break up a pattern into a valid token stream" {
    const allocator = testing.allocator;
    var lexer = Self.init("a\\.b*c");
    const tokens = try lexer.tokenize(allocator);
    defer allocator.free(tokens);

    const expected = [_]Token{
        .{ .typ = .CHAR, .val = 'a', .pos = 0 },
        .{ .typ = .ESCAPED_CHAR, .val = '.', .pos = 1 },
        .{ .typ = .CHAR, .val = 'b', .pos = 3 },
        .{ .typ = .STAR, .val = '*', .pos = 4 },
        .{ .typ = .CHAR, .val = 'c', .pos = 5 },
        .{ .typ = .EOF, .val = null, .pos = 6 },
    };

    for (tokens, 0..) |token, i| {
        try testing.expectEqual(expected[i].typ, token.typ);
        try testing.expectEqual(expected[i].val, token.val);
        try testing.expectEqual(expected[i].pos, token.pos);
    }
}
