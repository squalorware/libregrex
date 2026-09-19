const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");
const Lexer = @import("../Lexer.zig");
const Parser = @import("./Parser.zig").Parser;
const syntax = @import("../syntax.zig");
const tokens = @import("../tokens.zig");
const ErrorSet = types.errors.ErrorSet;
const Rune = unicode.Rune;
const RuneRange = unicode.ranges.RuneRange;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;
const Token = tokens.Token;
const TokenType = tokens.TokenType;

const RangeList = T_ManagedArrayList(RuneRange, null);
const RuneList = T_ManagedArrayList(u21, null);

/// Applies a predefined Unicode character-class escape to its corresponding regular or negated class set.
fn applyPresetEscape(
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

/// Returns Token's literal if this Token can represent a part of character class
fn charClassLiteral(token: Token) ?u21 {
    return switch (token.typ) {
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

/// Parses a character class after the opening `LBRACKET`
pub fn parseCharClass(ptr: *Parser) ErrorSet!syntax.CharClass {
    const negated = ptr.match(.CARET);

    var ranges = try RangeList.init(ptr.alloc, null);
    defer ranges.deinit();

    var chars = try RuneList.init(ptr.alloc, null);
    defer chars.deinit();

    var preset: syntax.PresetClassSet = .{};
    var negated_preset: syntax.PresetClassSet = .{};

    while (ptr.current().typ != .RBRACKET and ptr.current().typ != .EOF) {
        const start_token = ptr.current();

        // A leading or otherwise standalone unescaped '-' is a literal.
        if (start_token.typ == .DASH) {
            _ = ptr.advance();

            try chars.append('-');
            continue;
        }

        // Predefined character classes retain their regex semantics
        // inside bracket classes.
        if (start_token.typ == .ESCAPED_CHAR) {
            const val = start_token.val.?.raw();

            if (applyPresetEscape(val, &preset, &negated_preset)) {
                _ = ptr.advance();
                continue;
            }
        }

        const start = charClassLiteral(start_token) orelse {
            return ErrorSet.UnexpectedToken;
        };

        _ = ptr.advance();

        // If no '-' follows, this is an individual literal member.
        if (!ptr.match(.DASH)) {
            try chars.append(start);
            continue;
        }

        // A '-' immediately before ']' is a literal hyphen rather than a
        // range separator: `[a-]` represents `a` and `-`.
        if (ptr.current().typ == .RBRACKET) {
            try chars.append(start);
            try chars.append('-');
            break;
        }

        const end_token = ptr.current();

        // Preset classes cannot be range endpoints. Expressions such as
        // `[a-\d]` have no meaningful scalar endpoint.
        if (end_token.typ == .ESCAPED_CHAR and Lexer.isSemanticEscape(end_token.val.?.raw())) {
            return ErrorSet.UnexpectedToken;
        }

        const end = charClassLiteral(end_token) orelse {
            return ErrorSet.UnexpectedToken;
        };

        _ = ptr.advance();

        try ranges.append(.{
            .start = start,
            .end = end,
        });
    }

    if (!ptr.match(.RBRACKET)) {
        return ErrorSet.UnmatchedBracket;
    }

    return .{
        .ranges = try ranges.toOwnedSlice(),
        .chars = try chars.toOwnedSlice(),
        .preset = preset,
        .negated_preset = negated_preset,
        .negated = negated,
    };
}

const initTestParser = @import("./Parser.zig").initTestParser;

test "Should parse anchored lowercase character class repeat" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "^[a-z]*$");
    defer parser.deinit();

    const ast = try parser.parse();
    switch (ast.*) {
        .Sequence => |seq| {
            try std.testing.expectEqual(@as(usize, 3), seq.nodes.len);
            try std.testing.expect(seq.nodes[0].* == .StartAnchor);
            switch (seq.nodes[1].*) {
                .Repeat => |rep| {
                    try std.testing.expectEqual(@as(usize, 0), rep.min);
                    try std.testing.expectEqual(@as(?usize, null), rep.max);

                    switch (rep.node.*) {
                        .CharClass => |cls| {
                            try std.testing.expectEqual(false, cls.negated);
                            try std.testing.expectEqual(@as(usize, 1), cls.ranges.len);
                            try std.testing.expectEqual(@as(u21, 'a'), cls.ranges[0].start);
                            try std.testing.expectEqual(@as(u21, 'z'), cls.ranges[0].end);
                        },
                        else => try std.testing.expect(false),
                    }
                },
                else => try std.testing.expect(false),
            }
            try std.testing.expect(seq.nodes[2].* == .EndAnchor);
        },
        else => try std.testing.expect(false),
    }
}

test "Should parse predefined Unicode character classes" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "\\d\\D\\w\\W\\s\\S");
    defer parser.deinit();

    const ast = try parser.parse();
    switch (ast.*) {
        .Sequence => |seq| {
            try std.testing.expectEqual(
                @as(usize, 6),
                seq.nodes.len,
            );

            switch (seq.nodes[0].*) {
                .CharClass => |cls| {
                    try std.testing.expect(cls.preset.contains(.digit));
                    try std.testing.expect(!cls.negated_preset.contains(.digit));
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[1].*) {
                .CharClass => |cls| {
                    try std.testing.expect(!cls.preset.contains(.digit));
                    try std.testing.expect(cls.negated_preset.contains(.digit));
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[2].*) {
                .CharClass => |cls| {
                    try std.testing.expect(cls.preset.contains(.word));
                    try std.testing.expect(!cls.negated_preset.contains(.word));
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[3].*) {
                .CharClass => |cls| {
                    try std.testing.expect(!cls.preset.contains(.word));
                    try std.testing.expect(cls.negated_preset.contains(.word));
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[4].*) {
                .CharClass => |cls| {
                    try std.testing.expect(cls.preset.contains(.whitespace));
                    try std.testing.expect(!cls.negated_preset.contains(.whitespace));
                },
                else => try std.testing.expect(false),
            }

            switch (seq.nodes[5].*) {
                .CharClass => |cls| {
                    try std.testing.expect(!cls.preset.contains(.whitespace));
                    try std.testing.expect(cls.negated_preset.contains(.whitespace));
                },
                else => try std.testing.expect(false),
            }
        },

        else => try std.testing.expect(false),
    }
}

test "Should parse predefined classes inside bracket character class" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = try initTestParser(arena.allocator(), "[a-z\\d_\\S]");
    defer parser.deinit();

    const ast = try parser.parse();
    switch (ast.*) {
        .CharClass => |cls| {
            try std.testing.expectEqual(
                @as(usize, 1),
                cls.ranges.len,
            );

            try std.testing.expectEqual(
                @as(u21, 'a'),
                cls.ranges[0].start,
            );

            try std.testing.expectEqual(
                @as(u21, 'z'),
                cls.ranges[0].end,
            );

            try std.testing.expectEqual(
                @as(usize, 1),
                cls.chars.len,
            );

            try std.testing.expectEqual(
                @as(u21, '_'),
                cls.chars[0],
            );

            try std.testing.expect(
                cls.preset.contains(.digit),
            );

            try std.testing.expect(
                cls.negated_preset.contains(.whitespace),
            );
        },

        else => try std.testing.expect(false),
    }
}
