const std = @import("std");
const AST = @import("./ast.zig");
const Error = @import("../../common/errors.zig").Error;
const Lexer = @import("../lexer/root.zig");
const Rune = @import("../../common/types.zig").Rune;
const Token = @import("../lexer/token.zig");

const ParserError = Error || std.mem.Allocator.Error;
const TokenType = Token.TokenType;

pub const Parser = @This();

alloc: std.mem.Allocator,
group_count: usize = 0,
pos: usize = 0,
tokens: []const Token,

pub fn init(
    alloc: std.mem.Allocator,
    tokens: []const Token
) Parser {
    return .{
        .alloc = alloc,
        .tokens = tokens,
    };
}

fn current(self: *const Parser) Token {
    return self.tokens[self.pos];
}

fn peek(self: *Parser, offset: usize) ?Token {
    const idx = self.pos + offset;

    if (idx >= self.tokens.len) {
        return null;
    }

    return self.tokens[idx];
}

fn advance(self: *Parser) Token {
    const token = self.current();
    self.pos += 1;
    return token;
}

fn match(self: *Parser, typ: TokenType) bool {
    if (self.current().typ == typ) {
        _ = self.advance();
        return true;
    }
    return false;
}

fn expect(self: *Parser, typ: TokenType) !Token {
    if (self.current().typ != typ) {
        return Error.UnexpectedToken;
    }
    return self.advance();
}

fn createNode(self: *Parser, node: AST.Node) ParserError!*AST.Node {
    const ptr = try self.alloc.create(AST.Node);
    ptr.* = node;
    return ptr;
}

fn parseBranch(self: *Parser) ParserError!*AST.Node {
    var left = try self.parseSequence();

    while (self.match(.PIPE)) {
        const right = try self.parseSequence();
        left = try self.createNode(.{
            .Branch = .{
                .left = left,
                .right = right,
            },
        });
    }
    return left;
}

fn parseSequence(self: *Parser) ParserError!*AST.Node {
    var nodes = std.ArrayList(*AST.Node).empty;
    errdefer nodes.deinit(self.alloc);

    while(
        self.current().typ != .EOF and
        self.current().typ != .RPAREN and
        self.current().typ != .PIPE
    ) {
        const node = try self.parseQuantified();
        try nodes.append(self.alloc, node);
    }

    if (nodes.items.len == 0) {
        return Error.ExpectedExpression;
    }

    if (nodes.items.len == 1) {
        const only = nodes.items[0];
        nodes.deinit(self.alloc);
        return only;
    }

    const owned = try nodes.toOwnedSlice(self.alloc);

    return self.createNode(.{
        .Sequence = .{
            .nodes = owned,
        },
    });
}

fn parseQuantified(self: *Parser) ParserError!*AST.Node {
    const node = try self.parseAtom();

    if (self.match(.STAR)) {
        return self.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 0,
                .max = null,
            },
        });
    }

    if (self.match(.PLUS)) {
        return self.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 1,
                .max = null,
            },
        });
    }

    if (self.match(.QUESTION)) {
        return self.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 0,
                .max = 1,
            },
        });
    }
    return node;
}

fn parseAtom(self: *Parser) ParserError!*AST.Node {
    const token = self.current();

    switch (token.typ) {
        .CHAR, .ESCAPED_CHAR => {
            _ = self.advance();
            return self.createNode(.{
                .Literal = .{
                    .value = token.val.?,
                },
            });
        },
        .DOT => {
            _ = self.advance();
            return self.createNode(.{ .AnyChar = .{} });
        },
        .CARET => {
            _ = self.advance();
            return self.createNode(.{ .StartAnchor = .{} });            
        },
        .DOLLAR => {
            _ = self.advance();
            return self.createNode(.{ .EndAnchor = .{} });    
        },
        .LPAREN => {
            _ = self.advance();
            return self.parseGroup();
        },
        .LBRACKET => {
            _ = self.advance();
            const class = try self.parseCharClass();

            return self.createNode(.{
                .CharClass = class,
            });
        },
        else => return Error.UnexpectedToken,
    }
}

fn parseGroup(self: *Parser) ParserError!*AST.Node {
    const first = self.peek(0);
    const next = self.peek(1);

    if (
        first != null and 
        next != null and
        first.?.typ == .QUESTION and
        next.?.typ == .CHAR and
        next.?.val.? == ':'
    ) {
        _ = self.advance(); // QUESTION
        _ = self.advance(); // CHAR ':'

        const node= try self.parseBranch();

        if (!self.match(.RPAREN)) {
            return Error.ExpectedClosingParen;
        }

        return self.createNode(.{
            .NonCaptureGroup = .{
                .node = node,
            },
        });
    }

    self.group_count += 1;
    const pos = self.group_count;

    const node = try self.parseBranch();

    if (!self.match(.RPAREN)) {
        return Error.ExpectedClosingParen;
    }

    return self.createNode(.{
        .CaptureGroup = .{
            .pos = pos,
            .node = node,
        },
    });
}

fn parseCharClass(self: *Parser) ParserError!AST.CharClass {
    const negated = self.match(.CARET);

    var ranges = std.ArrayList(AST.CharRange).empty;
    errdefer ranges.deinit(self.alloc);

    var chars = std.ArrayList(Rune).empty;
    errdefer chars.deinit(self.alloc);

    while (
        self.current().typ != .RBRACKET and 
        self.current().typ != .EOF
    ) {
        const start_token = self.current();

        if (
            start_token.typ != .CHAR and 
            start_token.typ != .ESCAPED_CHAR
        ) {
            return Error.UnexpectedToken;
        }

        _ = self.advance();
        const start = start_token.val.?;

        if (self.match(.DASH)) {
            const end_token = self.current();

            if (end_token.typ == .RBRACKET) {
                try chars.append(self.alloc, start);
                try chars.append(self.alloc, '-');
                break;
            }

            if (
                end_token.typ != .CHAR and
                end_token.typ != .ESCAPED_CHAR
            ) {
                return Error.UnexpectedToken;
            }
            _ = self.advance();
            try ranges.append(self.alloc, .{
                .start = start,
                .end = end_token.val.?,
            });
        } else {
            try chars.append(self.alloc, start);
        }
    }
    if (!self.match(.RBRACKET)) {
        return Error.ExpectedClosingBracket;
    }
    return .{
        .ranges = try ranges.toOwnedSlice(self.alloc),
        .chars = try chars.toOwnedSlice(self.alloc),
        .negated = negated,
    };
}

pub fn parse(self: *Parser) ParserError!*AST.Node {
    const ast = try self.parseBranch();

    if (self.current().typ != .EOF) {
        return Error.UnexpectedToken;
    }
    return ast;
}

const testing = std.testing;

test "Should parse anchored lowercase character class repeat" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init("^[a-z]*$");
    const tokens = try lexer.tokenize(alloc);
    defer alloc.free(tokens);

    var parser = Parser.init(alloc, tokens);
    const ast = try parser.parse();

    switch (ast.*) {
        .Sequence => |seq| {
            try testing.expectEqual(@as(usize, 3), seq.nodes.len);
            try testing.expect(seq.nodes[0].* == .StartAnchor);
            switch (seq.nodes[1].*) {
                .Repeat => |rep| {
                    try testing.expectEqual(@as(usize, 0), rep.min);
                    try testing.expectEqual(@as(?usize, null), rep.max);

                    switch (rep.node.*) {
                        .CharClass => |cls| {
                            try testing.expectEqual(false, cls.negated);
                            try testing.expectEqual(@as(usize, 1), cls.ranges.len);
                            try testing.expectEqual(@as(Rune, 'a'), cls.ranges[0].start);
                            try testing.expectEqual(@as(Rune, 'z'), cls.ranges[0].end);
                        },
                        else => try testing.expect(false),
                    }
                },
                else => try testing.expect(false),
            }
            try testing.expect(seq.nodes[2].* == .EndAnchor);
        },
        else => try testing.expect(false),
    }
}

test "Should parse non-capturing group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var lexer = Lexer.init("(?:ab)+");
    const tokens = try lexer.tokenize(alloc);
    defer alloc.free(tokens);

    var parser = Parser.init(alloc, tokens);
    const ast = try parser.parse();

    switch (ast.*) {
        .Repeat => |rep| {
            try testing.expectEqual(@as(usize, 1), rep.min);
            try testing.expectEqual(@as(?usize, null), rep.max);

            switch (rep.node.*) {
                .NonCaptureGroup => |grp| {
                    switch (grp.node.*) {
                        .Sequence => |seq| {
                            try testing.expectEqual(@as(usize, 2), seq.nodes.len);

                            switch (seq.nodes[0].*) {
                                .Literal => |lit| try testing.expectEqual(@as(Rune, 'a'), lit.value),
                                else => try testing.expect(false),
                            }
                            switch (seq.nodes[1].*) {
                                .Literal => |lit| try testing.expectEqual(@as(Rune, 'b'), lit.value),
                                else => try testing.expect(false),
                            }
                        },
                        else => try testing.expect(false),
                    }
                },
                else => try testing.expect(false),
            }
        },
        else => try testing.expect(false),
    }
}
