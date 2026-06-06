const regrex = @import("root.zig");

export fn regrex_compile() void {
    regrex.compile();
}

export fn regrex_search() void {
    regrex.search();
}

export fn regrex_match() void {
    regrex.match();
}

export fn regrex_getAllMatches() void {
    regrex.getAllMatches();
}
