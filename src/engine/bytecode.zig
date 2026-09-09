//! Intermediate Code Representation.
//! 
//! Provides bytecode instruction definitions
//! for the virtual machine executing regular expressions
const Allocator = @import("std").mem.Allocator;
const ManagedDynamicBuffer = @import("types").ManagedDynamicBuffer;
const AST = @import("./syntax.zig");

/// A pair of bytecode addresses used by `Instruction.Split`
pub const Split = struct {
    first: usize,
    second: usize,
};

/// Matcher for an exact Unicode code point.
pub const RuneMatcher = struct {
    value: u21,
    ignore_case: bool = false,
};

/// Matcher for the `.` wildcard.
pub const AnyMatcher = struct {
    dot_all: bool = false,
};

/// Matcher for a character class.
pub const ClassMatcher = struct {
    class: AST.CharClass,
    ignore_case: bool = false,
};

/// Matcher for `^` and `$` anchors.
pub const AnchorMatcher = struct {
    multiline: bool = false,
};

/// A single VM instruction
pub const Instruction = union(enum) {
    /// Match one exact Unicode code point
    Rune: RuneMatcher,
    /// Match any single Unicode code point
    Any: AnyMatcher,
    /// Match one code point against a character class
    Class: ClassMatcher,
    /// Assert the current input position is the input start
    AssertStart: AnchorMatcher,
    /// Assert the current input position is the input end
    AssertEnd: AnchorMatcher,
    /// Assert `\A`, `\Z`, `\b` or `\B`
    Assert: AST.AssertionType,
    /// Save the current input position into a capture slot.
    ///
    /// Slots are arranged as pairs:
    /// - slot 0 / 1: whole match start/end
    /// - slot 2 / 3: group 1 start/end
    /// - slot 4 / 5: group 2 start/end
    Save: usize,
    /// Temporary instruction that holds current input position 
    /// until patched (replaced at index) by another instruction like Split or Jump
    Hold,
    /// Backtracking branch.
    ///
    /// The VM continues with `first` and pushes `second` onto the backtracking
    /// stack.
    Split: Split,
    /// An unconditional jump to another bytecode offset
    Jump: usize,
    /// A successful match terminator
    Match,
};

/// Callback to release memory allocated for CharClass fields
pub fn deinitInstruction(allocator: Allocator, item: *Instruction) void {
    switch (item.*) {
        .Class => |cls| {
            allocator.free(cls.class.ranges);
            allocator.free(cls.class.chars);
        },
        else => {},
    }
}

/// Managed buffer containing compiled VM instructions.
pub const BytecodeBuffer = ManagedDynamicBuffer(Instruction, deinitInstruction);
