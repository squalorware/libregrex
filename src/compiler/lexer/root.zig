const std = @import("std");
const Error = @import("../../common/errors.zig").Error;
const Rune = @import("../../common/types.zig").Rune;
const Token = @import("./token.zig");
const TokenType = Token.TokenType;
const mapRuneToTokenType = Token.mapRuneToTokenType;

pub const Lexer = @This();

pattern: []const u8,
pos: usize = 0,

pub fn init(pattern: []const u8) Lexer {
    return .{
        .pattern = pattern,
        .pos = 0,
    };
}

pub fn tokenize(self: *Lexer, alloc: std.mem.Allocator) ![]Token {
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

            try list.append(alloc, .{ 
                .typ = .ESCAPED_CHAR, 
                .val = escaped, 
                .pos = current_pos, 
            });
            continue;
        }

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

test {
    _ = @import("token.zig");
}

test "Should break up a pattern into valid tokens" {
    const allocator = testing.allocator;
    var lexer = Lexer.init("a\\.b*c");
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
