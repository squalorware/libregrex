const std = @import("std");
const types = @import("types");
const Parser = @import("./Parser.zig").Parser;
const syntax = @import("../syntax.zig");
const ErrorSet = types.errors.ErrorSet;

pub fn parseRepeatNumber(ptr: *Parser) ErrorSet!usize {
    var value: usize = 0;
    var found = false;

    while (ptr.current().id == .CHAR) {
        const rune = ptr.current().lexeme orelse break;
        const char = rune.raw();

        if (char < '0' or char > '9') break;
        found = true;

        value = std.math.mul(usize, value, 10) catch return ErrorSet.InvalidRepeat;
        _ = ptr.advance();
    }

    if (!found) return ErrorSet.InvalidRepeat;

    return value;
}

pub fn parseBoundedRepeat(ptr: *Parser, node: *syntax.Node) ErrorSet!*syntax.Node {
    _ = try ptr.expect(.LBRACE);

    const min = try parseRepeatNumber(ptr);
    if (ptr.match(.RBRACE)) {
        return ptr.createNode(.{
            .Repeat = .{ .node = node, .min = min, .max = min },
        });
    }

    _ = try ptr.expect(.COMMA);
    if (ptr.match(.RBRACE)) {
        return ptr.createNode(.{
            .Repeat = .{ .node = node, .min = min, .max = null },
        });
    }

    const max = try parseRepeatNumber(ptr);

    if (max < min) return ErrorSet.InvalidRepeat;

    _ = try ptr.expect(.RBRACE);
    return ptr.createNode(.{
        .Repeat = .{ .node = node, .min = min, .max = max },
    });
}
