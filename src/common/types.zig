//! Shared primitive types used across Regrex engine.

/// A Unicode scalar value.
/// 
/// Regrex performs matching at Unicode code point level
/// instead of native Zig UTF-8 byte slices.
/// 
/// Used to represent parsed literals, character class entries, 
/// decoded input characters etc.
pub const Rune = u21;

/// A decoded UTF-8 code point and its original byte length.
/// 
/// Byte length is required because match spans are byte offsets
/// while matching itself is performed on decoded code points
pub const DecodedRune = struct {
    /// Unicode scalar value
    rune: Rune,
    /// Bytes consumed from original input
    len: usize,
};

/// Byte-indexed interval into an input string.
///
/// Follows Zig slice semantics (`start` is inclusive; `end` is exclusive):
/// `input[start..end]`
pub const Group = struct {
    start: usize,
    end: usize,
};
