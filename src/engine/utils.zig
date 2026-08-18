const RegrexError = @import("types").Error;
const unicode = @import("unicode");
const Rune = unicode.Rune;
const AST = @import("./syntax.zig");
const bytecode = @import("./bytecode.zig");

/// Represents a rule by which a Rune-consuming Instruction should test it.
/// 
/// This lets `.Rune`, `.Any`, and `.Class` share the same consume/decode path
/// while preserving their distinct matching semantics.
pub const CurrentRuneMatcher = union(enum) {
    any: bytecode.AnyMatcher,
    literal: bytecode.RuneMatcher,
    char_class: bytecode.ClassMatcher,
};

fn rangeMatches(literal: u21, range: unicode.ranges.RuneRange, ignore_case: bool) bool {
    if (ignore_case) {
        return unicode.ranges.isCaseFold(range, literal);
    } else {
        return range.contains(literal);
    }
}

fn matchRanges(literal: u21, ranges: []const AST.CharClass, ignore_case: bool) bool {
    for (ranges) |range| {
        if (rangeMatches(literal, range, ignore_case)) return true;
    }
    return false;
}

fn matchChars(rune: Rune, chars: []const u21, ignore_case: bool) bool {
    for (chars) |char| {
        if (rune.equals(char, ignore_case)) return true;
    }
    return false;
}

fn matchPreset(literal: u21, preset: AST.PresetClassSet) bool {
    return (
        preset.match(literal, .digit) or
        preset.match(literal, .word) or
        preset.match(literal, .whitespace)
    );
}

fn matchNegatedPreset(literal: u21, preset: AST.PresetClassSet) bool {
    return (
        preset.matchNegated(literal, .digit) or
        preset.matchNegated(literal, .word) or
        preset.matchNegated(literal, .whitespace)
    );
}

/// Checks whether a Rune is accepted by a CharClass
///
/// Character classes are represented as a set of explicit runes
/// plus a set of inclusive rune ranges.
///
/// Negated classes invert the final result
fn matchCharClasses(rune: Rune, matcher: bytecode.ClassMatcher) bool {
    const cls = matcher.class;
    const matched = (
        matchRanges(rune.raw(), cls.ranges, matcher.ignore_case ) or
        matchChars(rune, cls.chars, matcher.ignore_case) or
        matchPreset(rune.raw(), cls.preset) or
        matchNegatedPreset(rune.raw(), cls.preset)
    );

    return if (cls.negated) !matched else matched;
}

/// Checks whether a Rune satisfies the provided matcher
pub fn matchRune(char: u21, matcher: CurrentRuneMatcher) RegrexError!bool {
    const rune = try Rune.from(char);
    switch (matcher) {
        .any => |m| {
            return m.dot_all or !rune.isLineBreak();
        },
        .literal => |m| {
            return rune.equals(m.value, m.ignore_case);
        },
        .char_class => |m| return matchCharClasses(rune, m),
    }
}
