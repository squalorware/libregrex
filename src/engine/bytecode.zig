//! Intermediate Code Representation.
//! 
//! Provides bytecode instruction definitions
//! for the virtual machine executing regular expressions
const ManagedArrayList = @import("types").ManagedArrayList;
const AST = @import("./syntax.zig");

/// A pair of bytecode addresses used by `Instruction.Split`
pub const Split = struct {
    first: usize,
    second: usize,
};

/// A single VM instruction
pub const Instruction = union(enum) {
    /// Match one exact Unicode code point
    Rune: u21,
    /// Match any single Unicode code point
    Any,
    /// Match one code point against a character class
    Class: AST.CharClass,
    /// Assert the current input position is the input start
    AssertStart,
    /// Assert the current input position is the input end
    AssertEnd,
    /// Save the current input position into a capture slot.
    ///
    /// Slots are arranged as pairs:
    /// - slot 0 / 1: whole match start/end
    /// - slot 2 / 3: group 1 start/end
    /// - slot 4 / 5: group 2 start/end
    Save: usize,
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

fn freeInstructionCallback(list: *InstructionList) void {
    for (list.items()) |*inst| {
        switch (inst.*) {
            .Class => |cls| {
                list.alloc.free(cls.ranges);
                list.alloc.free(cls.chars);
            },
            else => {},
        }
    }
}
pub const InstructionList = ManagedArrayList(Instruction, freeInstructionCallback);
