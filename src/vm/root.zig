// const testing = @import("std").testing;
// const pattern = @import("./pattern.zig");
// const iter = @import("./Iterator.zig");

// pub const Bytecode = @import("./bytecode.zig");
// pub const Compiler = @import("./Compiler.zig");
// pub const lexing = @import("./lexing/root.zig");
// pub const parsing = @import("./parsing/root.zig");
// pub const VM = @import("./VM.zig");
// pub const LazyIterator = iter.LazyIterator;
// pub const Lexer = lexing.Lexer;
// pub const Parser = parsing.Parser;
// pub const PatternSubOptions = pattern.PatternSubOptions;
// pub const Pattern = pattern.Pattern;
// pub const syntax = parsing.syntax;

// test {
//     _ = @import("./Compiler.zig");
//     _ = @import("./VM.zig");
//     _ = @import("./lexing/tokens.zig");
//     _ = @import("./lexing/escapes.zig");
//     _ = @import("./lexing/root.zig");
//     _ = @import("./parsing/root.zig");
//     _ = @import("./parsing/char_classes.zig");
//     _ = @import("./parsing/escapes.zig");
//     _ = @import("./parsing/groups.zig");
// }
const std = @import("std");
const types = @import("types");
const regexp = @import("regexp");
const unicode = @import("unicode");
const stack = @import("./stack.zig");
const decodeAt = unicode.decodeAt;
const decodePrev = unicode.decodePrev;
const ErrorSet = types.errors.ErrorSet;
const Match = types.Match;
const syntax = regexp.syntax;

pub const StackMachine = struct {
    alloc: std.mem.Allocator,
    prog: []const u8,
    classes: []syntax.CharClass,
    captures_count: usize,

    pub fn init(alloc: std.mem.Allocator, ctx: regexp.CompileOutput) StackMachine {
        const bcode = alloc.dupe(u8, ctx.prog) catch {
            return ErrorSet.MemoryError;
        };
        errdefer alloc.free(bcode);

        const char_classes = alloc.dupe(syntax.CharClass, ctx.classes) catch {
            return ErrorSet.MemoryError;
        };
        errdefer syntax.CharClass.freeCharClasses(alloc, char_classes);

        return .{
            .alloc = std.mem.Allocator,
            .prog = bcode,
            .classes = char_classes,
            .captures_count = ctx.captures_count,
        };
    }

    pub fn deinit(self: *StackMachine) void {
        const alloc = self.alloc;
        alloc.free(self.prog);

        syntax.CharClass.freeCharClasses(alloc, self.classes);

        self.* = undefined;
    }

    pub fn exec(self: *StackMachine, alloc: std.mem.Allocator, input: []const u8, start_pos: usize) ErrorSet!?Match {
        var ctx = try stack.ExecutionContext.init(alloc, start_pos, self.captures_count);
        defer ctx.deinit();

        while (true) {
            if (ctx.pc >= self.prog.len) {
                if (ctx.backtrack(self.alloc)) continue;
                return null;
            }
        }
    }
};
