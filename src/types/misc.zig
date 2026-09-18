pub const CompileFlags = packed struct(u8) {
    /// Pattern matching become case-insensitive
    ignore_case: bool = false,
    /// `^` and `$` mark start and end of a line
    multiline: bool = false,
    /// Wildcards match newline characters
    dot_all: bool = false,
    _padding: u5 = 0,

    /// Converts an unsigned 8-bit integer bitmask to internal flag type
    pub fn fromIntBitmask(bitmask: u8) CompileFlags {
        return .{
            .ignore_case = bitmask & (1 << 0) != 0,
            .multiline = bitmask & (1 << 1) != 0,
            .dot_all = bitmask & (1 << 2) != 0,
        };
    }
};

pub const LookupOrder = enum {
    before,
    match,
    after,
};
pub const LookupFn = enum { match, search };
pub const LookupSource = enum { root, pattern };

/// C ABI memory layout compatibility flag
pub const RangeOptions = struct {
    extern_compat: bool = false,
};
