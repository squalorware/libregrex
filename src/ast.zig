const Rune = @import("types.zig").Rune;

pub const Node = union(enum) {
    Literal: Literal,
    AnyChar: AnyChar,
    StartAnchor: StartAnchor,
    EndAnchor: EndAnchor,
    CharRange: CharRange,
    CharClass: CharClass,
    Sequence: Sequence,
    Alternation: Alternation,
    Repeat: Repeat,
    CaptureGroup: CaptureGroup,
    NonCaptureGroup: NonCaptureGroup,
};

pub const Literal = struct {
    value: Rune,
};

pub const AnyChar = struct {};

pub const StartAnchor = struct {};

pub const EndAnchor = struct {};

pub const CharRange = struct {
    start: Rune,
    end: Rune,
};

pub const CharClass = struct {
    ranges: []const CharRange,
    chars: []const Rune,
    negated: bool = false,
};

pub const Sequence = struct {
    nodes: []const *Node,
};

pub const Alternation = struct {
    left: *Node,
    right: *Node,
};

pub const Repeat = struct {
    node: *Node,
    min: usize,
    max: ?usize,
};

pub const CaptureGroup = struct {
    pos: usize,
    node: *Node,
};

pub const NonCaptureGroup = struct {
    node: *Node,
};
