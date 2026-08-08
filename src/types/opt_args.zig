/// Available options accepted both by `regrex.sub` and `regrex.Pattern.sub`
pub const SubOptions = struct {
    /// Maximum number of occurences to replace
    /// 
    /// `0` means replacing all occurences (default) 
    count: usize = 0,
};
