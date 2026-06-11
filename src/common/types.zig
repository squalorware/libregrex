/// Unicode scalar value.  
pub const Rune = u21;

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const Capture = ?Span;
