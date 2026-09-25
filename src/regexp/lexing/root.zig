const std = @import("std");
const types = @import("types");
const Rune = @import("unicode").Rune;
const escapes = @import("./escapes.zig");
const tokens = @import("./tokens.zig");
const ErrorSet = types.errors.ErrorSet;
const conv = types.conv;
const T_ManagedArrayList = types.T_ManagedArrayList;

const Buffer = T_ManagedArrayList(Token, null);

pub const Lexeme = tokens.Lexeme;
pub const Token = tokens.Token;
pub const TokenId = tokens.TokenId;

pub const Lexer = struct {
    pos: usize = 0,

    pub fn init() Lexer {
        return .{ .pos = 0 };
    }

    /// Consumes the string with pattern and breaks it down into an array of lexical tokens
    pub fn eval(self: *Lexer, alloc: std.mem.Allocator, pattern: []const u8) ErrorSet![]Token {
        var buffer = try Buffer.init(alloc, null);
        defer buffer.deinit();

        const view = std.unicode.Utf8View.init(pattern) catch {
            return ErrorSet.InvalidUnicode;
        };
        var iter = view.iterator();

        while (iter.nextCodepoint()) |char| {
            const current_pos = self.pos;
            self.pos += 1;

            if (char == '\\') {
                const escaped = iter.nextCodepoint() orelse {
                    return ErrorSet.TrailingEscape;
                };
                self.pos += 1;

                const literal = try escapes.normalize(&iter, escaped, &self.pos);
                const token = (try tokens.emitReservedEscapesOnly(escaped, literal, current_pos)) orelse (try tokens.emitLiteral(literal, current_pos));

                try buffer.append(token);
                continue;
            }
            const token = (try tokens.emitOperatorsOnly(char, current_pos)) orelse (try tokens.emitLiteral(char, current_pos));

            try buffer.append(token);
            continue;
        }
        try buffer.append(.{
            .EOP = .{ .val = null, .pos = self.pos },
        });

        return try buffer.toOwnedSlice();
    }
};

test "Should break up a pattern into a valid sequence of Tokens" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init();
    const result = try lexer.eval(allocator, "a\\.b*c");

    defer allocator.free(result);

    const expected = [_]Token{
        .{
            .CHAR = .{
                .val = try Rune.from('a'),
                .pos = 0,
            },
        },
        .{
            .CHAR = .{
                .val = try Rune.from('.'),
                .pos = 1,
            },
        },
        .{
            .CHAR = .{
                .val = try Rune.from('b'),
                .pos = 3,
            },
        },
        .{
            .STAR = .{
                .val = try Rune.from('*'),
                .pos = 4,
            },
        },
        .{
            .CHAR = .{
                .val = try Rune.from('c'),
                .pos = 5,
            },
        },
        .{ .EOP = .{ .val = null, .pos = 6 } },
    };

    try std.testing.expectEqualDeep(expected[0..], result);
}
