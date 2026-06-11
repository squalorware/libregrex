//! Recursively descending parser of the regular expression grammar
//! 
//! Consumes a `Token` stream emitted by `Lexer` and produces 
//! an arena-allocated Abstract Syntax Tree.
//! Implements a simple basic PCRE/Python-inspired grammar:
//! 
//! ```text
//! Branch      := Sequence ('|' Sequence)*
//! Sequence    := Quantified+
//! Quantified  := Atom ('*' | '+' | '?')?
//! Atom        := Literal | '.' | '^' | '$' | Group | CharClass
//! Group       := '(' Branch ')' | '(?:' Branch ')'
//! CharClass  := '[' '^'? class_item* ']'
//! ```
const std = @import("std");
const AST = @import("./ast.zig");
const Error = @import("../common/errors.zig").Error;
const Lexer = @import("./Lexer.zig");
const Rune = @import("../common/types.zig").Rune;
const Token = @import("./Token.zig");

const ParserError = Error || std.mem.Allocator.Error;
const TokenType = Token.TokenType;

/// Parser state instance for a single token stream
pub const Self = @This();

/// Controls AST lifetime.
alloc: std.mem.Allocator,
group_count: usize = 0,
pos: usize = 0,
/// Borrowed slice representing lexical token stream
tokens: []const Token,

/// `alloc`: controls AST nodes and owned child slices. 
/// 
/// Prefer an `ArenaAllocator`and release the whole 
/// AST after compiling to bytecode
pub fn init(
    alloc: std.mem.Allocator,
    tokens: []const Token
) Self {
    return .{
        .alloc = alloc,
        .tokens = tokens,
    };
}

/// Returns a token at the current 'cursor' position
fn current(self: *const Self) Token {
    return self.tokens[self.pos];
}

/// Returns a token at `pos + offset` or `null` 
/// if index out of range
fn peek(self: *Self, offset: usize) ?Token {
    const idx = self.pos + offset;

    if (idx >= self.tokens.len) {
        return null;
    }

    return self.tokens[idx];
}

/// Returns the current token and moves one position 'forward'
fn advance(self: *Self) Token {
    const token = self.current();
    self.pos += 1;
    return token;
}

/// Takes `TokenType` and checks if current token 
/// has matching type
fn match(self: *Self, typ: TokenType) bool {
    if (self.current().typ == typ) {
        _ = self.advance();
        return true;
    }
    return false;
}

/// Takes `TokenType` and checks if current token 
/// has matching type.
/// 
/// Returns `Error.UnexpectedToken` if type mismatch -
/// current token doesn't match context
fn expect(self: *Self, typ: TokenType) !Token {
    if (self.current().typ != typ) {
        return Error.UnexpectedToken;
    }
    return self.advance();
}

/// Allocates and initializes an AST Node
fn createNode(self: *Self, node: AST.Node) ParserError!*AST.Node {
    const ptr = try self.alloc.create(AST.Node);
    ptr.* = node;
    return ptr;
}

/// Parses branching.
/// 
/// Alteration has the lowest precedence in this grammar
fn parseBranch(self: *Self) ParserError!*AST.Node {
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

/// Parses a sequence of quantified Atoms until `EOF`, `RPAREN` or `PIPE`
fn parseSequence(self: *Self) ParserError!*AST.Node {
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
        return Error.ExpressionExpected;
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

/// Parses an Atom and an optional postfix quantifier (`*`, `+` or `?`)
fn parseQuantified(self: *Self) ParserError!*AST.Node {
    const node = try self.parseAtom();

    // Parse 'zero or more'
    if (self.match(.STAR)) {
        return self.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 0,
                .max = null,
            },
        });
    }

    // Parse 'one or more'
    if (self.match(.PLUS)) {
        return self.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 1,
                .max = null,
            },
        });
    }

    // Parse 'zero or one'
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

/// Parses the base indivisible expression
fn parseAtom(self: *Self) ParserError!*AST.Node {
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

/// Parses a capturing `(...)` or non-capturing `(?:...)` group
fn parseGroup(self: *Self) ParserError!*AST.Node {
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
            return Error.UnmatchedParen;
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
        return Error.UnmatchedParen;
    }

    return self.createNode(.{
        .CaptureGroup = .{
            .pos = pos,
            .node = node,
        },
    });
}

/// Parses a character class after parsing the opening `LBRACKET`
/// 
/// Supports:
/// - explicit characters
/// - inclusive ranges (e.g. `a-z`, `0-9`)
/// - escaped class members (e.g. `\*`)
/// - leading negation (`^`)
fn parseCharClass(self: *Self) ParserError!AST.CharClass {
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
        return Error.UnmatchedBracket;
    }
    return .{
        .ranges = try ranges.toOwnedSlice(self.alloc),
        .chars = try chars.toOwnedSlice(self.alloc),
        .negated = negated,
    };
}

/// Top-level callable.
/// 
/// Parses the whole `Token` stream and returns the whole AST
/// starting with root Node.
/// 
/// Returns `Error.UnexpectedToken` if the `Token` stream
/// does not end with `EOF`
pub fn parse(self: *Self) ParserError!*AST.Node {
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

    var parser = Self.init(alloc, tokens);
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

    var parser = Self.init(alloc, tokens);
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
