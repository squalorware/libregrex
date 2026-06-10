pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");


pub fn compile() void {}
pub fn search() void {}
pub fn match() void {}
pub fn getAllMatches() void {}


test {
    _ = @import("token.zig");
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
}
