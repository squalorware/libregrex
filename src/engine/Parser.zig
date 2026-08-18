const std = @import("std");
const types = @import("types");
const Rune = @import("unicode").Rune;
const AST = @import("./syntax.zig");
const Lexer = @import("./Lexer.zig");
const tokens = @import("./tokens.zig");
const testing = std.testing;
const RegrexError = types.Error;
const Token = tokens.Token;
const TokenType = tokens.TokenType;

/// Parser state instance for a single token stream
pub const Parser = @This();

/// Controls AST lifetime.
alloc: std.mem.Allocator,
group_count: usize = 0,
pos: usize = 0,
/// Borrowed slice representing lexical token stream
token_list: []const Token,

/// `alloc`: controls AST nodes and owned child slices. 
/// 
/// Prefer an `ArenaAllocator`and release the whole 
/// AST after compiling to bytecode
pub fn init(
    alloc: std.mem.Allocator,
    tlist: []const Token,
) Parser {
    return .{
        .alloc = alloc,
        .token_list = tlist,
    };
}

/// Returns a token at the current 'cursor' position
fn current(self: Parser) Token {
    return self.token_list[self.pos];
}

/// Returns a token at `pos + offset` or `null` 
/// if index out of range
fn peek(self: Parser, offset: usize) ?Token {
    const idx = self.pos + offset;

    if (idx >= self.token_list.len) {
        return null;
    }

    return self.token_list[idx];
}

/// Returns the current token and moves one position 'forward'
fn advance(self: *Parser) Token {
    const token = self.current();
    self.pos += 1;
    return token;
}

/// Takes `TokenType` and checks if current token 
/// has matching type
fn match(self: *Parser, typ: TokenType) bool {
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
fn expect(self: *Parser, typ: TokenType) RegrexError!Token {
    if (self.current().typ != typ) {
        return RegrexError.UnexpectedToken;
    }
    return self.advance();
}

/// Allocates and initializes an AST Node
fn createNode(self: *Parser, node: AST.Node) RegrexError!*AST.Node {
    const ptr = self.alloc.create(AST.Node) catch {
        return RegrexError.MemoryError;
    };
    ptr.* = node;
    return ptr;
}

/// Applies a predefined Unicode character-class escape to its corresponding
/// regular or negated class set.
///
/// Recognized escapes (regular, negated):
///
/// - `\d`, `\D` - any Unicode digit
/// - `\w`, `\W` - any Unicode word
/// - `\s`, `\S` - any Unicode whitespace
///
/// Returns `true` when `value` represents a predefined class.
fn applyPresetEscape(
    value: u21,
    preset: *AST.PresetClassSet,
    negated_preset: *AST.PresetClassSet,
) bool {
    switch(value) {
        'd' => preset.insert(.digit),
        'D' => negated_preset.insert(.digit),
        'w' => preset.insert(.word),
        'W' => negated_preset.insert(.word),
        's' => preset.insert(.whitespace),
        'S' => negated_preset.insert(.whitespace),
        else => return false,
    }
    return true;
}

/// Maps an escaped character to a zero-width assertion.
///
/// Returns `null` when the escape is not an assertion.
fn assertionEscape(value: u21) ?AST.AssertionType {
    return switch(value) {
        'A' => .start_abs,
        'Z' => .end_abs,
        'b' => .word_bounds,
        'B' => .non_word_bounds,
        else => null,
    };
}

/// Returns the literal scalar represented by a token when that token can act
/// as a literal character inside a bracket character class.
///
/// Most regex metacharacters lose their special meaning inside `[...]`.
fn charClassLiteral(token: Token) ?u21 {
    return switch(token.typ) {
        .CHAR,
        .ESCAPED_CHAR,
        .DOT,
        .CARET,
        .DOLLAR,
        .STAR,
        .PLUS,
        .QUESTION,
        .PIPE,
        .LPAREN,
        .RPAREN,
        .LBRACKET => token.val.?.raw(),
        else => null,
    };
}

/// Parses branching.
/// 
/// Alteration has the lowest precedence in this grammar
fn parseBranch(self: *Parser) RegrexError!*AST.Node {
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
fn parseSequence(self: *Parser) RegrexError!*AST.Node {
    var nodes = std.ArrayList(*AST.Node).empty;
    errdefer nodes.deinit(self.alloc);

    while(
        self.current().typ != .EOF and
        self.current().typ != .RPAREN and
        self.current().typ != .PIPE
    ) {
        const node = try self.parseQuantifier();
        nodes.append(self.alloc, node) catch {
            return RegrexError.MemoryError;
        };
    }

    if (nodes.items.len == 0) {
        return RegrexError.ExpressionExpected;
    }

    if (nodes.items.len == 1) {
        const only = nodes.items[0];
        nodes.deinit(self.alloc);
        return only;
    }

    const owned = nodes.toOwnedSlice(self.alloc) catch {
        return RegrexError.MemoryError;
    };

    return self.createNode(.{
        .Sequence = .{
            .nodes = owned,
        },
    });
}

/// Parses an Atom and an optional postfix quantifier (`*`, `+` or `?`)
fn parseQuantifier(self: *Parser) RegrexError!*AST.Node {
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

/// Parses an escaped atom carrying regex semantics.
///
/// Predefined class escapes are converted to `CharClass` nodes.
///
/// Assertion escapes are converted to `Assertion` nodes.
///
/// Any other escaped value is treated as a literal. This final case primarily
/// protects the parser from manually constructed token streams; the Lexer
/// normally emits non-semantic escaped literals as `CHAR`.
fn parseEscapedAtom(self: *Parser, token: Token) RegrexError!*AST.Node {
    _ = self.advance();

    const value = token.val.?.raw();

    var preset: AST.PresetClassSet = .{};
    var negated_preset: AST.PresetClassSet = .{};

    if (applyPresetEscape(value, &preset, &negated_preset)) {
        return self.createNode(.{
            .CharClass = .{
                .ranges = &.{},
                .chars = &.{},
                .preset = preset,
                .negated_preset = negated_preset,
            }
        });
    }

    if (assertionEscape(value)) |assert| {
        return self.createNode(.{
            .Assertion = .{
                .typ = assert,
            },
        });
    }

    return self.createNode(.{
        .Literal = .{
            .value = value,
        },
    });
}

/// Parses the base indivisible expression
fn parseAtom(self: *Parser) RegrexError!*AST.Node {
    const token = self.current();

     switch (token.typ) {
        .CHAR => {
            _ = self.advance();
            return self.createNode(.{
                .Literal = .{
                    .value = token.val.?.raw(),
                },
            });
        },
        .ESCAPED_CHAR => {
            return self.parseEscapedAtom(token);
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
        else => return RegrexError.UnexpectedToken,
    }
}

/// Parses a capturing `(...)` or non-capturing `(?:...)` group
fn parseGroup(self: *Parser) RegrexError!*AST.Node {
    const first = self.peek(0);
    const next = self.peek(1);

    // Parse a non-capturing group
    if (
        first != null and 
        next != null and
        first.?.typ == .QUESTION and
        next.?.typ == .CHAR and
        next.?.val.?.raw() == ':'
    ) {
        _ = self.advance(); // QUESTION
        _ = self.advance(); // CHAR ':'

        const node= try self.parseBranch();

        if (!self.match(.RPAREN)) {
            return RegrexError.UnmatchedParen;
        }

        return self.createNode(.{
            .NonCaptureGroup = .{
                .node = node,
            },
        });
    }
    // Parse a capturing group
    self.group_count += 1;
    const pos = self.group_count;

    const node = try self.parseBranch();

    if (!self.match(.RPAREN)) {
        return RegrexError.UnmatchedParen;
    }

    return self.createNode(.{
        .CaptureGroup = .{
            .pos = pos,
            .node = node,
        },
    });
}

/// Parses a character class after the opening `LBRACKET`
/// 
/// Supports:
/// - literal characters
/// - inclusive ranges (e.g. `a-z`, `0-9`)
/// - preset Unicode character classes (`\d`, `\w`, `\s`)
///  and their negated counterparts (`\D`, `\W`, `\S`)
/// - escaped class members and literals (e.g. `\*`)
/// - leading negation (`^`)
///
/// Assertions such as `\A` and `\b` do not act as assertions inside a
/// character class. In the current feature set they are treated as escaped
/// literal characters there.
fn parseCharClass(self: *Parser) RegrexError!AST.CharClass {
    const negated = self.match(.CARET);

    var ranges = std.ArrayList(AST.RuneRange).empty;
    errdefer ranges.deinit(self.alloc);

    var chars = std.ArrayList(u21).empty;
    errdefer chars.deinit(self.alloc);

    var preset: AST.PresetClassSet = .{};
    var negated_preset: AST.PresetClassSet = .{};

    while (
        self.current().typ != .RBRACKET and 
        self.current().typ != .EOF
    ) {
        const start_token = self.current();

        // A leading or otherwise standalone unescaped '-' is a literal.
        if (start_token.typ == .DASH) {
            _ = self.advance();

            chars.append(self.alloc, '-') catch {
                return RegrexError.MemoryError;
            };
            continue;
        }

        // Predefined character classes retain their regex semantics
        // inside bracket classes.
        if (start_token.typ == .ESCAPED_CHAR) {
            const value = start_token.val.?.raw();

            if (applyPresetEscape(
                value,
                &preset,
                &negated_preset,
            )) {
                _ = self.advance();
                continue;
            }
        }

        const start = charClassLiteral(start_token) orelse {
            return RegrexError.UnexpectedToken;
        };

        _ = self.advance();

        // If no '-' follows, this is an individual literal member.
        if (!self.match(.DASH)) {
            chars.append(self.alloc, start) catch {
                return RegrexError.MemoryError;
            };
            continue;
        }

        // A '-' immediately before ']' is a literal hyphen rather than a
        // range separator: `[a-]` represents `a` and `-`.
        if (self.current().typ == .RBRACKET) {
            chars.append(self.alloc, start) catch {
                return RegrexError.MemoryError;
            };

            chars.append(self.alloc, '-') catch {
                return RegrexError.MemoryError;
            };

            break;
        }

        const end_token = self.current();

        // Preset classes cannot be range endpoints. Expressions such as
        // `[a-\d]` have no meaningful scalar endpoint.
        if (
            end_token.typ == .ESCAPED_CHAR and
            Lexer.isSemanticEscape(end_token.val.?.raw())
        ) {
            return RegrexError.UnexpectedToken;
        }

        const end = charClassLiteral(end_token) orelse {
            return RegrexError.UnexpectedToken;
        };

        _ = self.advance();
        ranges.append(self.alloc, .{
            .start = start,
            .end = end,
        }) catch {
            return RegrexError.MemoryError;
        };
    }

    if (!self.match(.RBRACKET)) {
        return RegrexError.UnmatchedBracket;
    }

    return .{
        .ranges = ranges.toOwnedSlice(self.alloc) catch {
            return RegrexError.MemoryError;
        },
        .chars = chars.toOwnedSlice(self.alloc) catch {
            return RegrexError.MemoryError;
        },
        .preset = preset,
        .negated_preset = negated_preset,
        .negated = negated,
    };
}

/// Top-level callable.
/// 
/// Parses the whole `Token` stream and returns the whole AST
/// starting with root Node.
/// 
/// Returns `RegrexError.UnexpectedToken` if the `Token` stream
/// does not end with `EOF`
pub fn parse(self: *Parser) RegrexError!*AST.Node {
    const ast = try self.parseBranch();

    if (self.current().typ != .EOF) {
        return RegrexError.UnexpectedToken;
    }
    return ast;
}

test "Should parse anchored lowercase character class repeat" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(alloc, null);
    defer token_buffer.deinit();

    var lexer = Lexer.init("^[a-z]*$");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(alloc, token_buffer.items());
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
                            try testing.expectEqual(@as(u21, 'a'), cls.ranges[0].start);
                            try testing.expectEqual(@as(u21, 'z'), cls.ranges[0].end);
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
            try testing.expectEqual(@as(usize, 1), rep.min);
            try testing.expectEqual(@as(?usize, null), rep.max);

            switch (rep.node.*) {
                .NonCaptureGroup => |grp| {
                    switch (grp.node.*) {
                        .Sequence => |seq| {
                            try testing.expectEqual(@as(usize, 2), seq.nodes.len);

                            switch (seq.nodes[0].*) {
                                .Literal => |lit| try testing.expectEqual(@as(u21, 'a'), lit.value),
                                else => try testing.expect(false),
                            }
                            switch (seq.nodes[1].*) {
                                .Literal => |lit| try testing.expectEqual(@as(u21, 'b'), lit.value),
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

test "Should parse predefined Unicode character classes" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(
        alloc,
        null,
    );
    defer token_buffer.deinit();

    var lexer = Lexer.init("\\d\\D\\w\\W\\s\\S");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(
        alloc,
        token_buffer.items(),
    );

    const ast = try parser.parse();

    switch (ast.*) {
        .Sequence => |seq| {
            try testing.expectEqual(
                @as(usize, 6),
                seq.nodes.len,
            );

            switch (seq.nodes[0].*) {
                .CharClass => |cls| {
                    try testing.expect(cls.preset.contains(.digit));
                    try testing.expect(!cls.negated_preset.contains(.digit));
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[1].*) {
                .CharClass => |cls| {
                    try testing.expect(!cls.preset.contains(.digit));
                    try testing.expect(cls.negated_preset.contains(.digit));
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[2].*) {
                .CharClass => |cls| {
                    try testing.expect(cls.preset.contains(.word));
                    try testing.expect(!cls.negated_preset.contains(.word));
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[3].*) {
                .CharClass => |cls| {
                    try testing.expect(!cls.preset.contains(.word));
                    try testing.expect(cls.negated_preset.contains(.word));
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[4].*) {
                .CharClass => |cls| {
                    try testing.expect(cls.preset.contains(.whitespace));
                    try testing.expect(!cls.negated_preset.contains(.whitespace));
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[5].*) {
                .CharClass => |cls| {
                    try testing.expect(!cls.preset.contains(.whitespace));
                    try testing.expect(cls.negated_preset.contains(.whitespace));
                },
                else => try testing.expect(false),
            }
        },

        else => try testing.expect(false),
    }
}

test "Should parse predefined classes inside bracket character class" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(
        alloc,
        null,
    );
    defer token_buffer.deinit();

    var lexer = Lexer.init("[a-z\\d_\\S]");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(
        alloc,
        token_buffer.items(),
    );

    const ast = try parser.parse();

    switch (ast.*) {
        .CharClass => |cls| {
            try testing.expectEqual(
                @as(usize, 1),
                cls.ranges.len,
            );

            try testing.expectEqual(
                @as(u21, 'a'),
                cls.ranges[0].start,
            );

            try testing.expectEqual(
                @as(u21, 'z'),
                cls.ranges[0].end,
            );

            try testing.expectEqual(
                @as(usize, 1),
                cls.chars.len,
            );

            try testing.expectEqual(
                @as(u21, '_'),
                cls.chars[0],
            );

            try testing.expect(
                cls.preset.contains(.digit),
            );

            try testing.expect(
                cls.negated_preset.contains(.whitespace),
            );
        },

        else => try testing.expect(false),
    }
}

test "Should parse absolute and word-boundary assertions" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(
        alloc,
        null,
    );
    defer token_buffer.deinit();

    var lexer = Lexer.init("\\A\\bX\\B\\Z");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(
        alloc,
        token_buffer.items(),
    );

    const ast = try parser.parse();

    switch (ast.*) {
        .Sequence => |seq| {
            try testing.expectEqual(
                @as(usize, 5),
                seq.nodes.len,
            );

            switch (seq.nodes[0].*) {
                .Assertion => |assertion| {
                    try testing.expectEqual(
                        AST.AssertionType.start_abs,
                        assertion.typ,
                    );
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[1].*) {
                .Assertion => |assertion| {
                    try testing.expectEqual(
                        AST.AssertionType.word_bounds,
                        assertion.typ,
                    );
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[2].*) {
                .Literal => |lit| {
                    try testing.expectEqual(
                        @as(u21, 'X'),
                        lit.value,
                    );
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[3].*) {
                .Assertion => |assertion| {
                    try testing.expectEqual(
                        AST.AssertionType.non_word_bounds,
                        assertion.typ,
                    );
                },
                else => try testing.expect(false),
            }

            switch (seq.nodes[4].*) {
                .Assertion => |assertion| {
                    try testing.expectEqual(
                        AST.AssertionType.end_abs,
                        assertion.typ,
                    );
                },
                else => try testing.expect(false),
            }
        },

        else => try testing.expect(false),
    }
}

test "Should preserve decoded escaped literals as literal AST nodes" {
    const allocator = testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var token_buffer = try tokens.TokenListBuffer.init(
        alloc,
        null,
    );
    defer token_buffer.deinit();

    var lexer = Lexer.init("\\n\\r\\t\\x41\\101");
    try lexer.tokenize(&token_buffer);

    var parser = Parser.init(
        alloc,
        token_buffer.items(),
    );

    const ast = try parser.parse();

    const expected = [_]u21{
        '\n',
        '\r',
        '\t',
        'A',
        'A',
    };

    switch (ast.*) {
        .Sequence => |seq| {
            try testing.expectEqual(
                expected.len,
                seq.nodes.len,
            );

            for (seq.nodes, expected) |node, value| {
                switch (node.*) {
                    .Literal => |lit| {
                        try testing.expectEqual(
                            value,
                            lit.value,
                        );
                    },

                    else => try testing.expect(false),
                }
            }
        },

        else => try testing.expect(false),
    }
}
