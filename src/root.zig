pub const lexer = @import("lexer.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");


pub fn compile() void {}
pub fn search() void {}
pub fn match() void {}
pub fn getAllMatches() void {}


comptime {
    const root = @This();
    for (@typeInfo(root).@"struct".decls) |decl| {
        const _Decl = @TypeOf(@field(root, decl.name));
        if (_Decl == void) continue;

        if (!@hasDecl(root, decl.name)) {
            @compileError("Missing declaration: " ++ decl.name);
        }

        if (_Decl != @TypeOf(@field(root, decl.name))) {
            @compileError("Declaration has wrong type: " ++ decl.name);
        }
    }
}

test {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
}
