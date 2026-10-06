const std = @import("std");
const types = @import("types");
const bytecode = @import("./bytecode/root.zig");
const compiler = @import("./compiler.zig");
const states = @import("./states.zig");
const lexing = @import("./lexing/root.zig");
const Parser = @import("./parsing/Parser.zig").Parser;
const ErrorSet = types.errors.ErrorSet;
const Lexer = lexing.Lexer;
const Token = lexing.Token;
const CompileStateBuffer = states.CompileStateBuffer;

pub const syntax = @import("./syntax.zig");
pub const T_Operand = bytecode.T_Operand;
pub const Opcode = bytecode.Opcode;
pub const InstructionView = bytecode.InstructionView;
pub const CompileOutput = states.CompileOutput;
pub const ParserOutput = states.ParserOutput;

fn tokenize(gpa: std.mem.Allocator, input: []const u8) ErrorSet![]Token {
    var lexer = Lexer.init();
    return try lexer.eval(gpa, input);
}

fn buildSyntaxTree(gpa: std.mem.Allocator, tokens: []Token) ErrorSet!ParserOutput {
    var parser = Parser.init(gpa, tokens);
    defer parser.deinit();

    const node = try parser.parse();
    return ParserOutput{
        .syntax_tree = node,
        .inline_flags = parser.inlineFlags(),
        .captures_count = parser.captures_count,
    };
}

fn emitBytecode(gpa: std.mem.Allocator, parsed: ParserOutput, flags: syntax.Flags) ErrorSet!CompileOutput {
    const combined_flags = flags.merge(parsed.inline_flags);

    var buffers = try CompileStateBuffer.init(gpa, combined_flags);
    defer buffers.deinit();

    _ = try bytecode.emit(&buffers, .Save, 0);
    try compiler.compileNode(&buffers, parsed.syntax_tree);
    _ = try bytecode.emit(&buffers, .Save, 1);
    _ = try bytecode.emit(&buffers, .Match, null);

    return CompileOutput{
        .prog = try buffers.prog.toOwnedSlice(),
        .classes = try buffers.classes.toOwnedSlice(),
        .captures_count = parsed.captures_count,
    };
}

pub fn compilePattern(gpa: std.mem.Allocator, pattern: []const u8, flags: syntax.Flags) ErrorSet!CompileOutput {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const alloc = arena.allocator();

    const tokens = try tokenize(alloc, pattern);
    const parsed = try buildSyntaxTree(alloc, tokens);

    return try emitBytecode(alloc, parsed, flags);
}

pub fn readInstruction(gpa: std.mem.Allocator, comptime T: type, comptime opcode: Opcode, prog: []const u8, pc: usize) bytecode.InstructionView {
    var prog_count: usize = pc;

    // const op = try bytecode.Opcode.read(prog, pc);
    // prog_count += 1;

    // const OpType = comptime switch (op) {
    //     .TESTR => u21,
    //     .TESTA => u8,
    //     else => usize,
    // };

    const flags: ?syntax.Flags = if (opcode.usesFlags()) blk: {
        const mods = try bytecode.readFlags(prog, prog_count);
        prog_count += 1;
        break :blk mods;
    } else null;

    var operands: ?[]T = null;
    if (opcode.hasOperands()) {
        const oper = comptime opcode.opInfo().?;
        operands = gpa.alloc(T, oper.count) catch {
            return ErrorSet.MemoryError;
        };

        var i: usize = 0;
        while (i < oper.count) : (i += 1) {
            operands[i] = try bytecode.readOperand(opcode, prog, prog_count);
            prog_count += oper.size();
        }
    }
    return try bytecode.InstructionView(T).init(gpa, prog, opcode, flags, operands, .{
        .start = pc,
        .end = prog_count,
    });
}

test {
    _ = @import("./lexing/tokens.zig");
    _ = @import("./lexing/escapes.zig");
    _ = @import("./lexing/root.zig");
    _ = @import("./parsing/root.zig");
    _ = @import("./parsing/char_classes.zig");
    _ = @import("./parsing/escapes.zig");
    _ = @import("./parsing/groups.zig");
    _ = @import("./bytecode/opcodes.zig");
    _ = @import("./bytecode/operands.zig");
    _ = @import("./bytecode/root.zig");
    _ = @import("./compiler.zig");
    _ = @import("./states.zig");
    _ = @import("./syntax.zig");
}
