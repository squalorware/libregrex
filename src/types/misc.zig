/// Flags to tell regex compiler how to modify pattern behaviour
pub const CompileFlags = packed struct(u8) {
    /// Pattern matching become case-insensitive
    ignore_case: bool = false,
    /// `^` and `$` mark start and end of a line
    multiline: bool = false,
    /// Wildcards match newline characters
    dot_all: bool = false,
    _padding: u5 = 0,
};

pub const LookupOrder = enum {
    before,
    match,
    after,
};

/// C ABI memory layout compatibility flag
pub const RangeOptions = struct {
    extern_compat: bool = false,
};

