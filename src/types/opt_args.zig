/// Available options accepted both by `regrex.sub` and `regrex.Pattern.sub`
pub const SubOptions = struct {
    /// Maximum number of occurrences to replace
    /// 
    /// `0` means replacing all occurrences (default)
    count: usize = 0,
};
