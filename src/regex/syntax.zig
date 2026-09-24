//! The Abstract Syntax Tree representation
//! of the regular expression pattern.
const unicode = @import("unicode");

pub const Flags = packed struct(u8) {
    /// Pattern matching becomes case-insensitive
    ignore_case: bool = false,
    /// `^` and `$` mark start and end of a line
    multiline: bool = false,
    /// Wildcards match newline characters
    dot_all: bool = false,
    _padding: u5 = 0,

    /// Converts an unsigned 8-bit integer bitmask to internal flag type
    pub fn fromIntBitmask(bitmask: u8) Flags {
        return .{
            .ignore_case = bitmask & (1 << 0) != 0,
            .multiline = bitmask & (1 << 1) != 0,
            .dot_all = bitmask & (1 << 2) != 0,
        };
    }

    pub fn toIntBitmask(self: Flags) u8 {
        var bitmask: u8 = 0;

        if (self.ignore_case) bitmask |= (1 << 0);
        if (self.multiline) bitmask |= (1 << 1);
        if (self.dot_all) bitmask |= (1 << 2);

        return bitmask;
    }

    /// Add up flags received at various stages, e.g. inline flags + flags as args to compile
    pub fn merge(self: Flags, other: Flags) Flags {
        return .{
            .ignore_case = self.ignore_case or other.ignore_case,
            .multiline = self.multiline or other.multiline,
            .dot_all = self.dot_all or other.dot_all,
        };
    }
};

/// Regular Expression AST Node.
///
/// Forms a recursive tree structure with pointers to another Nodes
pub const Node = union(enum) {
    /// Literal Unicode code point
    Literal: Literal,
    /// `.` Wildcard
    AnyChar: AnyChar,
    /// `^` Input start anchor
    StartAnchor: StartAnchor,
    /// `$` Input end anchor
    EndAnchor: EndAnchor,
    /// Zero-width assertions (e.g. `\A`, `\Z` etc.)
    Assertion: Assertion,
    /// Character class (e.g. `[a-z]`, `[0-9]` etc.)
    CharClass: CharClass,
    /// Concatenation of multiple Nodes
    Sequence: Sequence,
    /// `|` Alternation
    Branch: Branch,
    /// Quantifier node (`*`, `+` or `?`)
    Repeat: Repeat,
    /// Capturing group `(...)`
    CaptureGroup: CaptureGroup,
    /// Non-capturing group `(?:...)`
    NonCaptureGroup: NonCaptureGroup,
};

/// Literal Unicode code point
pub const Literal = struct {
    value: u21,
};

/// `.` Wildcard
pub const AnyChar = struct {};

/// `^` Input start anchor.
///
/// If flag `multiline == true` then acts as the line start anchor
pub const StartAnchor = struct {};

/// `$` Input end anchor.
///
/// If flag `multiline == true` then acts as the line end anchor
pub const EndAnchor = struct {};

/// Zero-width assertion type.
pub const AssertionType = enum(u8) {
    /// Absolute start of the input marked by `\A`.
    start_abs,
    /// Absolute end of the input marked by `\A`.
    end_abs,
    /// Word boundary marked by `\b`.
    word_bounds,
    /// Non-word boundary marked by `\B`.
    non_word_bounds,
};

/// Zero-width assertion expression.
pub const Assertion = struct {
    typ: AssertionType,
};

/// Inclusive character range used inside a character class.
pub const RuneRange = unicode.ranges.RuneRange;

/// Predefined Unicode character class.
pub const PresetClass = unicode.ranges.CharClassType;

/// Set of predefined Unicode character classes.
pub const PresetClassSet = packed struct(u8) {
    digit: bool = false,
    word: bool = false,
    whitespace: bool = false,
    _padding: u5 = 0,

    /// Adds a preset character class to the set.
    pub fn insert(self: *PresetClassSet, cls: PresetClass) void {
        switch (cls) {
            .digit => self.digit = true,
            .word => self.word = true,
            .whitespace => self.whitespace = true,
        }
    }

    /// Checks whether a preset character class is enabled.
    pub fn contains(self: PresetClassSet, cls: PresetClass) bool {
        return switch (cls) {
            .digit => self.digit,
            .word => self.word,
            .whitespace => self.whitespace,
        };
    }

    /// Checks whether a scalar matches an enabled preset character class.
    pub fn match(self: PresetClassSet, literal: u21, cls: PresetClass) bool {
        if (self.contains(cls) and unicode.ranges.isInClass(cls, literal)) {
            return true;
        }
        return false;
    }

    /// Checks whether a scalar matches an enabled negated preset character class.
    pub fn matchNegated(self: PresetClassSet, literal: u21, cls: PresetClass) bool {
        if (self.contains(cls) and !unicode.ranges.isInClass(cls, literal)) {
            return true;
        }
        return false;
    }
};

/// Character-class expression.
///
/// `ranges`: inclusive ranges such as `a-z` or `0-9`.
///
/// `chars`: individual literal members.
///
/// `negated`: classes beginning with `^`, such as `[^0-9]`.
pub const CharClass = struct {
    ranges: []const RuneRange,
    chars: []const u21,
    preset: PresetClassSet = .{},
    negated_preset: PresetClassSet = .{},
    negated: bool = false,
};

/// Concatenation of child nodes that must match in order.
pub const Sequence = struct {
    nodes: []const *Node,
};

/// Alternation between left and right child Nodes.
pub const Branch = struct {
    left: *Node,
    right: *Node,
};

/// Repetition Node
///
/// If `max`is `null` the repetition is without limit
pub const Repeat = struct {
    node: *Node,
    min: usize,
    max: ?usize,
};

/// Capturing group
pub const CaptureGroup = struct {
    /// Base-1 capture group index.
    /// Group 0 is reserved for the whole match
    pos: usize,
    node: *Node,
};

/// Non-capturing group.
pub const NonCaptureGroup = struct {
    node: *Node,
};

test "Should convert to bitmask and back again round through" {
    const std = @import("std");
    const flags: Flags = .{
        .ignore_case = true,
        .dot_all = true,
    };

    const decoded = Flags.fromIntBitmask(flags.toIntBitmask());

    try std.testing.expectEqual(flags.toIntBitmask(), decoded.toIntBitmask());
}

test "Should preserve enabled values from both inputs on merge" {
    const std = @import("std");
    const left: Flags = .{ .ignore_case = true };
    const right: Flags = .{ .multiline = true };
    const merged = left.merge(right);

    try std.testing.expect(merged.ignore_case);
    try std.testing.expect(merged.multiline);
    try std.testing.expect(!merged.dot_all);
}
