const std = @import("std");
const syntax = @import("../syntax.zig");
const types = @import("types");
const lexing = @import("../lexing/root.zig");
const ErrorSet = types.errors.ErrorSet;
const Token = lexing.Token;
const TokenType = lexing.TokenType;

const atomics = @import("./atomics.zig");
const classes = @import("./char_classes.zig");
const escapes = @import("./escapes.zig");
const groups = @import("./groups.zig");

pub const Parser = struct {
    alloc: std.mem.Allocator,
    captures_count: usize = 0,
    pos: usize = 0,
    tokens: []const Token,
    inline_flags: syntax.Flags = .{},

    /// Using `std.heap.ArenaAllocator` is recommended, this way the entire AST is released
    /// after being compiled to bytecode
    pub fn init(alloc: std.mem.Allocator, tlist: []const Token) Parser {
        return .{
            .alloc = alloc,
            .tokens = tlist,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.alloc.free(self.tokens);
    }

    pub fn inlineFlags(self: *Parser) syntax.Flags {
        return self.inline_flags;
    }

    /// Returns a token at the current 'cursor' position
    pub fn current(self: *Parser) Token {
        return self.tokens[self.pos];
    }

    /// Returns a token at `pos + offset` or `null` if index out of range
    pub fn peek(self: *Parser, offset: usize) ?Token {
        const idx = self.pos + offset;

        if (idx >= self.tokens.len) {
            return null;
        }

        return self.tokens[idx];
    }

    /// Returns the current token and moves one position 'forward'
    pub fn advance(self: *Parser) Token {
        const token = self.current();
        self.pos += 1;
        return token;
    }

    /// Checks if current token's type matches the expected one
    pub fn match(self: *Parser, tag: TokenType) bool {
        const t = self.current();
        if (t.tag() == tag) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    /// Returns a compilation error if token type doesn't match the expected one
    pub fn expect(self: *Parser, tag: TokenType) ErrorSet!Token {
        const t = self.current();
        if (t.tag() != tag) {
            return ErrorSet.UnexpectedToken;
        }
        return self.advance();
    }

    /// Parses branching.
    ///
    /// Alteration has the lowest precedence in this parsing
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
        while(groups.startsInlineFlags(self)) {
            try groups.parseInlineFlags(self);        
        }

        const ast = try self.parseBranch();

        if (self.current().tag() != .EOP) {
            return ErrorSet.UnexpectedToken;
        }
        return ast;
    }

};


pub fn initTestParser(alloc: std.mem.Allocator, pattern: []const u8) ErrorSet!Parser {
    var lexer = lexing.Lexer.init();
    const token_list = try lexer.eval(alloc, pattern);

    return Parser.init(alloc, token_list);
}
