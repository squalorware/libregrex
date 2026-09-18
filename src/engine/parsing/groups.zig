const std = @import("std");
const types = @import("types");
const Lexer = @import("../Lexer.zig");
const Parser = @import("./Parser.zig");
const syntax = @import("../syntax.zig");
const tokens = @import("../tokens.zig");
const ErrorSet = types.errors.ErrorSet;
const TokenType = tokens.TokenType;

pub const Flags = packed struct(u8) {
    /// Pattern matching becomes case-insensitive
    ignore_case: bool = false,
    /// `^` and `$` mark start and end of a line
    multiline: bool = false,
    /// Wildcards match newline characters
    dot_all: bool = false,
    _padding: u5 = 0,

    /// Converts an unsigned 8-bit integer bitmask to internal flag type
    pub fn fromIntBitmask(bitmask: u8) Flags {
        return .{
            .ignore_case = bitmask & (1 << 0) != 0,
            .multiline = bitmask & (1 << 1) != 0,
            .dot_all = bitmask & (1 << 2) != 0,
        };
    }

    /// Add up flags received at various stages, e.g. inline flags + flags as args to compile
    pub fn merge(self: Flags, other: Flags) Flags {
        return .{
            .ignore_case = self.ignore_case or other.ignore_case,
            .multiline = self.multiline or other.multiline,
            .dot_all = self.dot_all or other.dot_all,
        };
    }
};

pub fn inlineFlags(ptr: Parser) Flags {
    return ptr.inline_flags;
}

pub fn applyInlineFlag(flags: *Flags, rune: u21) bool {
    switch (rune) {
        'i' => flags.ignore_case = true,
        'm' => flags.multiline = true,
        's' => flags.dot_all = true,
        else => return false,
    }
    return true;
}

/// Parses a capturing `(...)` or non-capturing `(?:...)` group
pub fn parseGroup(ptr: *Parser) ErrorSet!*syntax.Node {
    const first = ptr.peek(0);
    const next = ptr.peek(1);

    // Parse a non-capturing group
    if (first != null and
        next != null and
        first.?.typ == .QUESTION and
        next.?.typ == .CHAR and
        next.?.val.?.raw() == ':')
    {
        _ = ptr.advance(); // QUESTION
        _ = ptr.advance(); // CHAR ':'

        const node = try ptr.parseBranch();

        if (!ptr.match(.RPAREN)) {
            return ErrorSet.UnmatchedParen;
        }

        return ptr.createNode(.{
            .NonCaptureGroup = .{
                .node = node,
            },
        });
    }
    // Parse a capturing group
    ptr.group_count += 1;
    const pos = ptr.group_count;

    const node = try ptr.parseBranch();

    if (!ptr.match(.RPAREN)) {
        return ErrorSet.UnmatchedParen;
    }

    return ptr.createNode(.{
        .CaptureGroup = .{
            .pos = pos,
            .node = node,
        },
    });
}

test "Should parse non-capturing group" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(alloc, null);
    defer token_buffer.deinit();

    var lexer = Lexer.init("(?:ab)+");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(alloc, token_buffer.items());
    const ast = try parser.parse();

    switch (ast.*) {
        .Repeat => |rep| {
            try std.testing.expectEqual(@as(usize, 1), rep.min);
            try std.testing.expectEqual(@as(?usize, null), rep.max);

            switch (rep.node.*) {
                .NonCaptureGroup => |grp| {
                    switch (grp.node.*) {
                        .Sequence => |seq| {
                            try std.testing.expectEqual(@as(usize, 2), seq.nodes.len);

                            switch (seq.nodes[0].*) {
                                .Literal => |lit| try std.testing.expectEqual(@as(u21, 'a'), lit.value),
                                else => try std.testing.expect(false),
                            }
                            switch (seq.nodes[1].*) {
                                .Literal => |lit| try std.testing.expectEqual(@as(u21, 'b'), lit.value),
                                else => try std.testing.expect(false),
                            }
                        },
                        else => try std.testing.expect(false),
                    }
                },
                else => try std.testing.expect(false),
            }
        },
        else => try std.testing.expect(false),
    }
}
