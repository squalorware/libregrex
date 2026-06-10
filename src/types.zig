/// A representation of a Unicode (UTF-8) character
pub const Rune = u21;

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const Capture = ?Span;
