const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");
const Bytecode = @import("./bytecode.zig");
const LazyIterator = @import("./Iterator.zig").LazyIterator;
const Instruction = Bytecode.Instruction;
const InstructionSet = Bytecode.InstructionSet;
const vm = @import("./VM.zig");
const ErrorSet = types.errors.ErrorSet;
const StringBuffer = types.StringBuffer;
const Match = types.Match;
const MatchListBuffer = types.MatchListBuffer;
const ExecutionContext = vm.ExecutionContext;

const _Pattern = struct {
    alloc: std.mem.Allocator,
    pattern: []const u8,
    instructions: []Instruction,
    group_count: usize,
};

pub const PatternSubOptions = struct {
    /// How many matches to replace (0 for replacing all; default)
    count: usize = 0,
};

/// Data structure produced by `regrex.compile()` representing a compiled pattern.
/// 
/// Points to a private structure which stores the runtime context. Fields `.pattern`, `.instructions`, 
/// `.group_count` and `.allocator` are private and accessed only by exposed public interface.
///  Owned and released by caller.
pub const Pattern = opaque {
    pub fn init(
        alloc: std.mem.Allocator,
        pattern: []const u8,
        bytecode: *InstructionSet,
        group_count: usize,
    ) ErrorSet!*Pattern {
        const self: *_Pattern = alloc.create(_Pattern) catch {
            return ErrorSet.MemoryError;
        };

        var instructions = try bytecode.toOwnedSlice();
        errdefer alloc.free(&instructions);

        self.* = .{
            .alloc = alloc,
            .pattern = pattern,
            .instructions = instructions,
            .group_count = group_count,
        };
        return @ptrCast(self);
    }

    /// Releases bytecode buffer and dereferences itself
    pub fn deinit(ptr: *Pattern) void {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));
        const alloc = self.alloc;

        for (self.instructions) |*inst| {
            Bytecode.freeInstructionCallback(self.alloc, inst);
        }
        alloc.free(self.instructions);
        self.* = undefined;
        alloc.destroy(self);
    }

    /// Returns the first match encountered at the beginning of the input
    pub fn match(ptr: *Pattern, input: []const u8) ErrorSet!?Match {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));

        return try vm.execAt(
            self.alloc,
            input,
            0,
            self.group_count,
            self.instructions
        );
    }

    /// Returns the first match produced at any position within the input
    pub fn search(ptr: *Pattern, input: []const u8) ErrorSet!?Match {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));
        var pos: usize = 0;

        while (pos <= input.len) {
            if (try vm.execAt(
                self.alloc,
                input,
                pos,
                self.group_count,
                self.instructions
            )) |m| return m;

            _ = unicode.advancePos(input, &pos) catch break;
        }
        return null;
    }

    /// Closure function which shares current execution context and Pattern state with LazyIterator
    fn vmExecClosure(
        ctx: *const anyopaque,
        opts: ExecutionContext,
    ) ErrorSet!?Match {
        const self: *const _Pattern = @ptrCast(@alignCast(ctx));

        return vm.execAt(
            self.alloc,
            opts.input,
            opts.pos,
            self.group_count,
            self.instructions,
        );
    }

    /// Initializes and returns an instance of the lazy iterator to perform lookups
    /// 
    /// The caller owns the instance and must release it explicitly by calling `iter.deinit(alloc)`
    pub fn findIter(ptr: *Pattern, input: []const u8) ErrorSet!*LazyIterator {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));

        return LazyIterator.init(
            self.alloc,
            self,
            input,
            vmExecClosure,
        );
    }

    /// Returns a slice containing all non-overlapping matches found in the input
    /// 
    /// The caller owns the slice and must explicitly release it
    pub fn findAll(ptr: *Pattern, input: []const u8) ErrorSet![]Match {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));

        var iter = try findIter(ptr, input);
        defer iter.deinit(self.alloc);

        var matches = try MatchListBuffer.init(self.alloc, .{});
        defer matches.deinit();

        while (try iter.next()) |m| try matches.append(m);

        return try matches.toOwnedSlice();
    }

    /// Copies the input string to a dynamic buffer, then substitutes all pattern matches with a replacement string
    /// 
    /// Returns the modified copy of the input. Returned slice is owned by caller and must be released
    pub fn sub(
        ptr: *Pattern,
        input: []const u8,
        repl: []const u8,
        opts: PatternSubOptions,
    ) ErrorSet![]u8 {
        const self: *_Pattern = @ptrCast(@alignCast(ptr));

        var out_buf = try StringBuffer.init(self.alloc, .{});
        defer out_buf.deinit();

        var iter = try findIter(ptr, input);
        defer iter.deinit(self.alloc);

        var copy_pos: usize = 0;
        var repl_count: usize = 0;

        while(opts.count == 0 or opts.count > repl_count) {
            const found = (try iter.next()) orelse break;

            var matched = found;
            defer matched.deinit();

            const start = try matched.start(0);
            const end = try matched.end(0);
            const next_pos = iter.resumePos();

            try out_buf.appendSlice(input[copy_pos..start]);
            try out_buf.appendSlice(repl);
            try out_buf.appendSlice(input[end..next_pos]);

            copy_pos = next_pos;
            repl_count += 1;
        }

        try out_buf.appendSlice(input[copy_pos..]);
        return try out_buf.toOwnedSlice();
    }
};
