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
const process = @import("./process.zig");
const decodeAt = unicode.decodeAt;
const decodePrev = unicode.decodePrev;
const ErrorSet = types.errors.ErrorSet;
const Match = types.Match;
const syntax = regexp.syntax;

pub const StackMachine = struct {
    gpa: std.mem.Allocator,
    prog: []const u8,
    classes: []syntax.CharClass,
    captures_count: usize,

    pub fn init(gpa: std.mem.Allocator, comp: regexp.CompileOutput) StackMachine {
        const bcode = gpa.dupe(u8, comp.prog) catch {
            return ErrorSet.MemoryError;
        };
        errdefer gpa.free(bcode);

        const char_classes = gpa.dupe(syntax.CharClass, comp.classes) catch {
            return ErrorSet.MemoryError;
        };
        errdefer syntax.CharClass.freeCharClasses(gpa, char_classes);

        return .{
            .gpa = std.mem.Allocator,
            .prog = bcode,
            .classes = char_classes,
            .captures_count = comp.captures_count,
        };
    }

    pub fn deinit(self: *StackMachine) void {
        const gpa = self.gpa;
        gpa.free(self.prog);

        syntax.CharClass.freeCharClasses(gpa, self.classes);

        self.* = undefined;
    }

    pub fn exec(self: *StackMachine, gpa: std.mem.Allocator, input: []const u8, start_pos: usize) ErrorSet!?Match {
        var ctx = try process.Context.init(gpa, start_pos, self.captures_count);
        defer ctx.deinit();

        while (true) {
            if (ctx.acc() >= self.prog.len) {
                if (ctx.backtrack(self.gpa)) continue;
                return null;
            }
            const opcode = try regexp.Opcode.read(self.prog, ctx.acc());
            const OpType = regexp.T_Operand(opcode);

            ctx.inc(1);

            const inst = try regexp.readInstruction(gpa, OpType, opcode, self.prog, ctx.acc());
            switch (inst.opcode.data) {}
        }
    }
};
