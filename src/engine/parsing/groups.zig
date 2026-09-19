const std = @import("std");
const types = @import("types");
const Lexer = @import("../Lexer.zig");
const Parser = @import("./Parser.zig").Parser;
const syntax = @import("../syntax.zig");
const tokens = @import("../tokens.zig");
const Flags = syntax.Flags;
const ErrorSet = types.errors.ErrorSet;
const Token = tokens.Token;
const TokenType = tokens.TokenType;

pub fn applyInlineFlag(flags: *syntax.Flags, rune: u21) bool {
    switch (rune) {
        'i' => flags.ignore_case = true,
        'm' => flags.multiline = true,
        's' => flags.dot_all = true,
        else => return false,
    }
    return true;
}

pub fn startsInlineFlags(ptr: *Parser) bool {
    const lparen = ptr.peek(0) orelse return false;
    const question = ptr.peek(1) orelse return false;
    const flag = ptr.peek(2) orelse return false;

    if (lparen.typ != .LPAREN or
        question.typ != .QUESTION or
        flag.typ != .CHAR) 
    {
        return false;
    }

    return switch(flag.val.?.raw()) {
        'i', 'm', 's' => true,
        else => false,
    };
}

pub fn parseInlineFlags(ptr: *Parser) ErrorSet!void {
    _ = try ptr.expect(.LPAREN);
    _ = try ptr.expect(.QUESTION);

    var found = false;

    while (ptr.current().typ == .CHAR) {
        const rune = ptr.current().val.?.raw();

        if (!applyInlineFlag(&ptr.inline_flags, rune)) break;
        
        found = true;
        _ = ptr.advance();
    }

    if (!found) return ErrorSet.UnexpectedToken;

    if (ptr.current().typ == .EOF) return ErrorSet.UnmatchedParen;
    _ = try ptr.expect(.RPAREN);
}

/// Parses a capturing `(...)` and non-capturing `(?:...)` group or an inline flag `(?ims)` expressions
pub fn parseGroup(ptr: *Parser) ErrorSet!*syntax.Node {
    const first = ptr.peek(0);
    const next = ptr.peek(1);

    // Parse inline flags or a non-capturing group
    if (first != null and first.?.typ == .QUESTION) {
        if (next == null) return ErrorSet.UnmatchedParen;
        if (next.?.typ != .CHAR) return ErrorSet.UnexpectedToken;

        const rune = next.?.val.?.raw();

        if (rune == ':') {
            _ = ptr.advance();
            _ = ptr.advance();

            const node = try ptr.parseBranch();

            if (!ptr.match(.RPAREN)) return ErrorSet.UnmatchedParen;

            return ptr.createNode(.{
                .NonCaptureGroup = .{ .node = node },
            });
        }
        // TODO: for now inline flags are accepted only at beginning
        if (rune == 'i' or rune == 'm' or rune == 's') {
            return ErrorSet.UnexpectedToken;
        }

        return ErrorSet.UnexpectedToken;
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

const initTestParser = @import("./Parser.zig").initTestParser;

test "Should parse non-capturing group" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "(?:ab)+");
    defer parser.deinit();

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

test "Should parse global inline ignore-case flag" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "(?i)foo");
    defer parser.deinit();

    const ast = try parser.parse();
    const flags = parser.inlineFlags();

    try std.testing.expect(flags.ignore_case);
    try std.testing.expect(!flags.multiline);
    try std.testing.expect(!flags.dot_all);

    switch (ast.*) {
        .Sequence => |seq| {
            try std.testing.expectEqual(@as(usize, 3), seq.nodes.len);
        },
        else => try std.testing.expect(false),
    }
}

test "Should parse combined global inline flags" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "(?ims)foo");
    defer parser.deinit();

    const ast = try parser.parse();
    const flags = parser.inlineFlags();

    try std.testing.expect(flags.ignore_case);
    try std.testing.expect(flags.multiline);
    try std.testing.expect(flags.dot_all);

    switch (ast.*) {
        .Sequence => |seq| {
            try std.testing.expectEqual(@as(usize, 3), seq.nodes.len);
        },
        else => try std.testing.expect(false),
    }
}

test "Should parse consequently repeated global inline flags" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "(?i)(?s)foo");
    defer parser.deinit();

    const ast = try parser.parse();
    const flags = parser.inlineFlags();

    try std.testing.expect(flags.ignore_case);
    try std.testing.expect(!flags.multiline);
    try std.testing.expect(flags.dot_all);

    switch (ast.*) {
        .Sequence => |seq| {
            try std.testing.expectEqual(@as(usize, 3), seq.nodes.len);
        },
        else => try std.testing.expect(false),
    }
}

test "Should return an Error in case of a misplaced global inline flag" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "foo(?i)bar");
    defer parser.deinit();

    try std.testing.expectError(ErrorSet.UnexpectedToken, parser.parse());
}