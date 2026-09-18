const std = @import("std");
const types = @import("types");
const Lexer = @import("../Lexer.zig");
const Parser = @import("./Parser.zig");
const syntax = @import("../syntax.zig");
const tokens = @import("../tokens.zig");
const ErrorSet = types.errors.ErrorSet;
const Token = tokens.Token;

/// Applies a predefined Unicode character-class escape to its corresponding
/// regular or negated class set.
pub fn applyPresetEscape(
    value: u21,
    preset: *syntax.PresetClassSet,
    negated_preset: *syntax.PresetClassSet,
) bool {
    switch (value) {
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
pub fn assertionEscape(value: u21) ?syntax.AssertionType {
    return switch (value) {
        'A' => .start_abs,
        'Z' => .end_abs,
        'b' => .word_bounds,
        'B' => .non_word_bounds,
        else => null,
    };
}

/// Parses an escaped sequence that may be a preset charclass, assertion or escaped literal
pub fn parseEscapedAtom(ptr: *Parser, token: Token) ErrorSet!*syntax.Node {
    _ = ptr.advance();

    const value = token.val.?.raw();

    var preset: syntax.PresetClassSet = .{};
    var negated_preset: syntax.PresetClassSet = .{};

    if (applyPresetEscape(value, &preset, &negated_preset)) {
        return ptr.createNode(.{ 
            .CharClass = .{
                .ranges = &.{},
                .chars = &.{},
                .preset = preset,
                .negated_preset = negated_preset,
            } 
        });
    }

    if (assertionEscape(value)) |assert| {
        return ptr.createNode(.{
            .Assertion = .{
                .typ = assert,
            },
        });
    }

    return ptr.createNode(.{
        .Literal = .{
            .value = value,
        },
    });
}

test "Should parse absolute and word-boundary assertions" {
    const allocator = std.testing.allocator;

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
            try std.testing.expectEqual(
                @as(usize, 5),
                seq.nodes.len,
            );

            switch (seq.nodes[0].*) {
                .Assertion => |assertion| {
                    try std.testing.expectEqual(
                        syntax.AssertionType.start_abs,
                        assertion.typ,
                    );
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[1].*) {
                .Assertion => |assertion| {
                    try std.testing.expectEqual(
                        syntax.AssertionType.word_bounds,
                        assertion.typ,
                    );
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[2].*) {
                .Literal => |lit| {
                    try std.testing.expectEqual(
                        @as(u21, 'X'),
                        lit.value,
                    );
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[3].*) {
                .Assertion => |assertion| {
                    try std.testing.expectEqual(
                        syntax.AssertionType.non_word_bounds,
                        assertion.typ,
                    );
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[4].*) {
                .Assertion => |assertion| {
                    try std.testing.expectEqual(
                        syntax.AssertionType.end_abs,
                        assertion.typ,
                    );
                },
                else => try std.testing.expect(false),
            }
        },

        else => try std.testing.expect(false),
    }
}

test "Should preserve decoded escaped literals as literal AST nodes" {
    const allocator = std.testing.allocator;

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
            try std.testing.expectEqual(
                expected.len,
                seq.nodes.len,
            );

            for (seq.nodes, expected) |node, value| {
                switch (node.*) {
                    .Literal => |lit| {
                        try std.testing.expectEqual(
                            value,
                            lit.value,
                        );
                    },

                    else => try std.testing.expect(false),
                }
            }
        },

        else => try std.testing.expect(false),
    }
}
