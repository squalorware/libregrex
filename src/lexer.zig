const std = @import("std");
const Error = @import("errors.zig").Error;

pub const Rune = u21;

pub const TokenType = enum {
    CHAR,
    ESCAPED_CHAR,
    DOT,
    CARET,
    DOLLAR,
    STAR,
    PLUS,
    QUESTION,
    PIPE,
    LPAREN,
    RPAREN,
    LBRACKET,
    RBRACKET,
    DASH,
    NEGATE,
    EOF,
};

pub const Token = struct {
    typ: TokenType,
    val: ?Rune,
    pos: usize = 0,
};

const MetaCharMapEntry = struct {
    rune: Rune,
    tokenType: TokenType,
};

pub const MetaCharMap = struct {
    pub const map = [_]MetaCharMapEntry{
        .{ .rune = '.', .tokenType = .DOT },
        .{ .rune = '^', .tokenType = .CARET },
        .{ .rune = '$', .tokenType = .DOLLAR },
        .{ .rune = '*', .tokenType = .STAR },
        .{ .rune = '+', .tokenType = .PLUS },
        .{ .rune = '?', .tokenType = .QUESTION },
        .{ .rune = '|', .tokenType = .PIPE },
        .{ .rune = '(', .tokenType = .LPAREN },
        .{ .rune = ')', .tokenType = .RPAREN },
        .{ .rune = '[', .tokenType = .LBRACKET },
        .{ .rune = ']', .tokenType = .RBRACKET },
        .{ .rune = '-', .tokenType = .DASH },
    };

    pub fn lookUp(r: Rune) ?TokenType {
        for (map) |entry| {
            if (entry.rune == r) {
                return entry.tokenType;
            }
        }
        return null;
    }
};

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
                return Error.DanglingEscape;
            };

            self.pos += 1;

            try list.append(alloc, .{ 
                .typ = .ESCAPED_CHAR, 
                .val = escaped, 
                .pos = current_pos, 
            });
            continue;
        }

        const typ = MetaCharMap.lookUp(rune) orelse .CHAR;

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

test "Lexer::MetaCharMap.lookUp" {
    const cases = [_]struct {
        input: Rune,
        expected: ?TokenType,
    }{
        .{ .input = '.', .expected = .DOT },
        .{ .input = '^', .expected = .CARET },
        .{ .input = '$', .expected = .DOLLAR },
        .{ .input = '*', .expected = .STAR },
        .{ .input = '+', .expected = .PLUS },
        .{ .input = '?', .expected = .QUESTION },
        .{ .input = '|', .expected = .PIPE },
        .{ .input = '(', .expected = .LPAREN },
        .{ .input = ')', .expected = .RPAREN },
        .{ .input = '[', .expected = .LBRACKET },
        .{ .input = ']', .expected = .RBRACKET },
        .{ .input = '-', .expected = .DASH },
        // Not a regex metacharacter
        .{ .input = 'a', .expected = null },
    };

    for (cases) |c| {
        const result = MetaCharMap.lookUp(c.input);
        try std.testing.expectEqual(c.expected, result);
    }
}

test "Lexer.tokenize" {
    const allocator = std.testing.allocator;
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
        try std.testing.expectEqual(expected[i].typ, token.typ);
        try std.testing.expectEqual(expected[i].val, token.val);
        try std.testing.expectEqual(expected[i].pos, token.pos);
    }
}
