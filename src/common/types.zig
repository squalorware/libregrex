//! Shared primitive types used across Regrex engine.

/// Unicode scalar value.  
pub const Rune = u21;

/// Byte-indexed interval into an input string.
///
/// Follows Zig slice semantics (`start` is inclusive; `end` is exclusive):
/// `input[start..end]`
pub const Span = struct {
    start: usize,
    end: usize,
};

/// Optional capture span.
///
/// `null` if the capture group did not participate in the match.
pub const Capture = ?Span;
