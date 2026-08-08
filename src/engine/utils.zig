const RegrexError = @import("types").Error;
const Rune = @import("unicode").Rune;
const AST = @import("./syntax.zig");

/// Represents a rule by which a Rune-consuming Instruction should test it.
/// 
/// This lets `.Rune`, `.Any`, and `.Class` share the same consume/decode path
/// while preserving their distinct matching semantics.
pub const RuneMatcher = union(enum) {
    any,
    literal: u21,
    char_class: AST.CharClass,
};

/// Checks whether a Rune is accepted by a CharClass
/// 
/// Character classes are represented as a set of explicit runes 
/// plus a set of inclusive rune ranges. 
/// 
/// Negated classes invert the final result
fn isInClass(rune: u21, cls: AST.CharClass) bool {
    var matched = false;

    for (cls.ranges) |range| {
        if (rune >= range.start and rune <= range.end) {
            matched = true;
            break;
        }
    }

    if (!matched) {
        for (cls.chars) |char| {
            if (rune == char) {
                matched = true;
                break;
            }
        }
    }
    return if (cls.negated) !matched else matched;
}

/// Checks whether a Rune satisfies the provided matcher
pub fn matchRune(rune: u21, matcher: RuneMatcher) bool {
    switch (matcher) {
        .any => return true,
        .literal => |lit| return rune == lit,
        .char_class => |cls| return isInClass(rune, cls),
    }
}

/// Advances one UTF-8 code point byte length to the next position 
/// 
/// If succeeds, updates position to point at the next Unicode character and returns `true`.
/// 
/// Returns `false` without changing position if the `input` is exhausted or meets the optional fail condition
/// 
/// Returns `Error.InvalidUnicode` if encounters broken UTF-8 
pub fn advanceOneRune(input: []const u8, pos: *usize, fail_condition: ?bool) RegrexError!bool {
    const rune = try Rune.from(input[pos.*]);
    const not_ok = fail_condition orelse (pos.* > input.len);

    if (not_ok) return false;
    
    pos.* += rune.len;
    return true;
}
