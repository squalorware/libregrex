//! The Abstract Syntax Tree representation 
//! of the regular expression pattern.
const unicode = @import("unicode");

/// Pattern behaviour modifiers
pub const Flags = packed struct(u8) {
    /// Case-insensitive matching
    ignore_case: bool = false,
    /// Interpret `^` and `$` as marking start and end
    /// of a single line instead of the whole input
    multiline: bool = false,
    /// Wildcards match newline characters as well
    dot_all: bool = false,
    _padding: u5 = 0,
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

pub const StartAnchor = struct {};

pub const EndAnchor = struct {};

pub const AssertionType = enum {
    /// Absolute start of the input marked by `\A`.
    ///
    /// Ignored if `multiline = false`
    start_abs,
    /// Absolute end of the input marked by `\A`.
    ///
    /// Ignored if `multiline = false`
    end_abs,
    word_bounds,
    non_word_bounds,
};

pub const Assertion = struct {
    typ: AssertionType,
};

/// Inclusive character range used inside a character class.
pub const RuneRange = unicode.ranges.RuneRange;

pub const PresetClass = unicode.ranges.CharClassType;

pub const PresetClassSet = packed struct (u8) {
    digit: bool = false,
    word: bool = false,
    whitespace: bool = false,
    _padding: u5 = 0,

    pub fn insert(self: *PresetClassSet, cls: PresetClass) void {
        switch (cls) {
            .digit => self.digit = true,
            .word => self.word = true,
            .whitespace => self.whitespace = true,
        }
    }

    pub fn contains(self: PresetClassSet, cls: PresetClass) bool {
        return switch (cls) {
            .digit => self.digit,
            .word => self.word,
            .whitespace => self.whitespace,
        };
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

pub const NonCaptureGroup = struct {
    node: *Node,
};
