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

/// Checks whether a scalar matches an explicit Rune range.
fn rangeMatches(literal: u21, range: unicode.ranges.RuneRange, ignore_case: bool) bool {
    if (ignore_case) {
        return unicode.ranges.isCaseFold(range, literal);
    } else {
        return range.contains(literal);
    }
}

/// Checks whether a scalar matches any explicit Rune range.
fn matchRanges(literal: u21, ranges: []const unicode.ranges.RuneRange, ignore_case: bool) bool {
    for (ranges) |range| {
        if (rangeMatches(literal, range, ignore_case)) return true;
    }
    return false;
}

/// Checks whether a Rune matches any explicit character.
fn matchChars(rune: Rune, chars: []const u21, ignore_case: bool) bool {
    for (chars) |char| {
        if (rune.equals(char, ignore_case)) return true;
    }
    return false;
}

/// Checks whether a scalar matches any enabled preset character class.
fn matchPreset(literal: u21, preset: AST.PresetClassSet) bool {
    return (
        preset.match(literal, .digit) or
        preset.match(literal, .word) or
        preset.match(literal, .whitespace)
    );
}

/// Checks whether a scalar matches any enabled negated preset character class.
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
        matchNegatedPreset(rune.raw(), cls.negated_preset)
    );

    return if (cls.negated) !matched else matched;
}

/// Checks whether a Rune satisfies the provided matcher
fn matchRune(rune: Rune, matcher: CurrentRuneMatcher) RegrexError!bool {
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

/// Checks the Rune at the current position in input and then advances it by Rune byte length
pub fn runeMatched(input: []const u8, pos: *usize, matcher: CurrentRuneMatcher) RegrexError!bool {
    const rune = try unicode.decodeAt(input, pos.*) orelse return false;
    if (!try matchRune(rune, matcher)) return false;

    unicode.stepRune(pos, rune);
    return true;
}

/// Checks whether current input position is a line start.
fn isLineStart(input: []const u8, pos: usize) RegrexError!bool {
    if (pos == 0) return true;

    const prev = try unicode.decodePrev(input, pos) orelse return false;
    if (prev.raw() == '\r') {
        const current = try unicode.decodeAt(input, pos);
        return current == null or current.?.raw() != '\n';
    }
    return prev.isLineBreak();
}

/// Checks whether current input position is a line end.
fn isLineEnd(input: []const u8, pos: usize) RegrexError!bool {
    if (pos == input.len) return true;

    const current = try unicode.decodeAt(input, pos) orelse return true;
    if (current.raw() == '\n') {
        const prev = try unicode.decodePrev(input, pos);
        return prev == null or prev.?.raw() != '\r';
    }
    return current.isLineBreak();
}

/// Checks whether a start or end anchor matches current input position.
pub fn anchorMatched(
    inst: bytecode.Instruction,
    input: []const u8,
    pos: usize,
    multiline: bool
) RegrexError!bool {
    switch (inst) {
        .AssertStart => {
            if (multiline) return try isLineStart(input, pos);
            return pos == 0;
        },
        .AssertEnd => {
            if (multiline) return try isLineEnd(input, pos);
            return pos == input.len;
        },
        else => return false,
    }
}

/// Checks whether current input position is a Unicode word boundary.
fn isWordBoundary(input: []const u8, pos: usize) RegrexError!bool {
    const prev = try unicode.decodePrev(input, pos);
    const current = try unicode.decodeAt(input, pos);

    return unicode.ranges.isWord(prev) == unicode.ranges.isWord(current);
}

/// Checks whether a zero-width assertion matches current input position.
pub fn assertMatched(input: []const u8, pos: usize, assert: AST.AssertionType) RegrexError!bool {
    return switch(assert) {
        .start_abs => pos == 0,
        .end_abs => pos == input.len,
        .word_bounds => try isWordBoundary(input, pos),
        .non_word_bounds => !try isWordBoundary(input, pos),
    };
}
