//! The Abstract Syntax Tree representation 
//! of the regular expression pattern.

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

/// Inclusive character range used inside a character class.
pub const CharRange = struct {
    start: u21,
    end: u21,
};

/// Character-class expression.
///
/// `ranges`: inclusive ranges such as `a-z` or `0-9`.
/// 
/// `chars`: individual literal members. 
/// 
/// `negated`: classes beginning with `^`, such as `[^0-9]`.
pub const CharClass = struct {
    ranges: []const CharRange,
    chars: []const u21,
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
