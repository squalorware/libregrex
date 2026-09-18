const std = @import("std");
const types = @import("types");
const classes = @import("./char_classes.zig");
const escapes = @import("./escapes.zig");
const groups = @import("./groups.zig");
const Parser = @import("./Parser.zig");
const syntax = @import("../syntax.zig");

const ErrorSet = types.errors.ErrorSet;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;

const NodeList = T_ManagedArrayList(*syntax.Node, null);

/// Parses a sequence of quantified Atoms until `EOF`, `RPAREN` or `PIPE`
pub fn parseSequence(ptr: *Parser) ErrorSet!*syntax.Node {
    var nodes = try NodeList.init(ptr.alloc, null);
    errdefer nodes.deinit();

    while (ptr.current().typ != .EOF and ptr.current().typ != .RPAREN and ptr.current().typ != .PIPE) {
        const node = try parseQuantifier(ptr);
        try nodes.append(node);
    }

    if (nodes.len() == 0) {
        return ErrorSet.ExpressionExpected;
    }

    if (nodes.len() == 1) {
        const only = nodes.items()[0];
        nodes.deinit();
        return only;
    }

    return ptr.createNode(.{
        .Sequence = .{
            .nodes = try nodes.toOwnedSlice(),
        },
    });
}

/// Parses an Atom and an optional postfix quantifier (`*`, `+` or `?`)
pub fn parseQuantifier(ptr: *Parser) ErrorSet!*syntax.Node {
    const node = try parseAtom(ptr);

    // Parse 'zero or more'
    if (ptr.match(.STAR)) {
        return ptr.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 0,
                .max = null,
            },
        });
    }

    // Parse 'one or more'
    if (ptr.match(.PLUS)) {
        return ptr.createNode(.{
            .Repeat = .{
                .node = node,
                .min = 1,
                .max = null,
            },
        });
    }

    // Parse 'zero or one'
    if (ptr.match(.QUESTION)) {
        return ptr.createNode(.{
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
pub fn parseAtom(ptr: *Parser) ErrorSet!*syntax.Node {
    const token = ptr.current();

    switch (token.typ) {
        .CHAR => {
            _ = ptr.advance();
            return ptr.createNode(.{
                .Literal = .{
                    .value = token.val.?.raw(),
                },
            });
        },
        .ESCAPED_CHAR => {
            return escapes.parseEscapedAtom(ptr, token);
        },
        .DOT => {
            _ = ptr.advance();
            return ptr.createNode(.{ .AnyChar = .{} });
        },
        .CARET => {
            _ = ptr.advance();
            return ptr.createNode(.{ .StartAnchor = .{} });
        },
        .DOLLAR => {
            _ = ptr.advance();
            return ptr.createNode(.{ .EndAnchor = .{} });
        },
        .LPAREN => {
            _ = ptr.advance();
            return groups.parseGroup(ptr);
        },
        .LBRACKET => {
            _ = ptr.advance();
            const class = try classes.parseCharClass(ptr);

            return ptr.createNode(.{
                .CharClass = class,
            });
        },
        else => return ErrorSet.UnexpectedToken,
    }
}
