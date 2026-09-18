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
