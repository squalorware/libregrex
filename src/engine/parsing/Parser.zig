const std = @import("std");
const syntax = @import("../syntax.zig");
const types = @import("types");
const tokens = @import("../tokens.zig");
const ErrorSet = types.errors.ErrorSet;
const Token = tokens.Token;
const TokenType = tokens.TokenType;

const atomics = @import("./atomics.zig");
const classes = @import("./char_classes.zig");
const escapes = @import("./escapes.zig");
const groups = @import("./groups.zig");

pub const Parser = @This();

alloc: std.mem.Allocator,
group_count: usize = 0,
pos: usize = 0,
token_list: []const Token,
inline_flags: groups.Flags = .{},

/// Using `std.heap.ArenaAllocator` is recommended, this way the entire AST is released
/// after being compiled to bytecode
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
pub fn current(self: Parser) Token {
    return self.token_list[self.pos];
}

/// Returns a token at `pos + offset` or `null` if index out of range
pub fn peek(self: Parser, offset: usize) ?Token {
    const idx = self.pos + offset;

    if (idx >= self.token_list.len) {
        return null;
    }

    return self.token_list[idx];
}

/// Returns the current token and moves one position 'forward'
pub fn advance(self: *Parser) Token {
    const token = self.current();
    self.pos += 1;
    return token;
}

/// Checks if current token's type matches the expected one
pub fn match(self: *Parser, typ: TokenType) bool {
    if (self.current().typ == typ) {
        _ = self.advance();
        return true;
    }
    return false;
}

/// Returns a compilation error if token type doesn't match the expected one
pub fn expect(self: *Parser, typ: TokenType) ErrorSet!Token {
    if (self.current().typ != typ) {
        return ErrorSet.UnexpectedToken;
    }
    return self.advance();
}

/// Parses branching.
///
/// Alteration has the lowest precedence in this grammar
pub fn parseBranch(self: *Parser) ErrorSet!*syntax.Node {
    var left = try atomics.parseSequence(self);

    while (self.match(.PIPE)) {
        const right = try atomics.parseSequence(self);
        left = try self.createNode(.{
            .Branch = .{
                .left = left,
                .right = right,
            },
        });
    }
    return left;
}

/// Allocates and initializes an AST Node
pub fn createNode(self: *Parser, node: syntax.Node) ErrorSet!*syntax.Node {
    const ptr = self.alloc.create(syntax.Node) catch {
        return ErrorSet.MemoryError;
    };
    ptr.* = node;
    return ptr;
}

/// Parses the lexical Token buffer into an abstract tree representation of a regular expression
pub fn parse(self: *Parser) ErrorSet!*syntax.Node {
    const ast = try self.parseBranch();

    if (self.current().typ != .EOF) {
        return ErrorSet.UnexpectedToken;
    }
    return ast;
}
