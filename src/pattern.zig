const std = @import("std");
const engine = @import("engine");
const types = @import("types");
const unicode = @import("unicode");
const FindIterator = engine.FindIterator;
const bytecode = engine.bytecode;
const vm = engine.VM;
const RegrexError = types.Error;
const DynamicStringBuffer = types.DynamicStringBuffer;
const Match = types.Match;
const MatchListBuffer = types.MatchListBuffer;
const SubOptions = types.opt_args.SubOptions;
const Rune = unicode.Rune;

/// Internal representation of a compiled regular expression pattern.
/// 
/// It is deliberatly unavailable from outside to prevent any malicious access.
/// Users can interact with it only through opaque top-level `Pattern` type. 
const CompiledPattern = struct {
    alloc: std.mem.Allocator,
    pattern: []const u8,
    instructions: []bytecode.Instruction,
    group_count: usize,
};

/// Opaque type to secure the internal CompiledPattern representation.
/// 
/// Ensures full encapsulation and exposes outside only a specific set of operations
/// without giving access to the compiled bytecode buffer itself
pub const Pattern = opaque {
    /// Copies the instructions from the dynamic buffer into internal storage
    ///
    /// The managed `BytecodeBuffer` is then released with `deinit`
    ///
    /// Returns a pointer to an opaque wrapper that does not expose any of `CompiledPattern` fields
    /// and provides a safe manipulation interface
    pub fn init(
        alloc: std.mem.Allocator,
        pattern: []const u8,
        inst_list: *bytecode.BytecodeBuffer,
        group_count: usize,
    ) RegrexError!*Pattern {
        const self: *CompiledPattern = alloc.create(CompiledPattern) catch {
            return RegrexError.MemoryError;
        };

        var instructions = try inst_list.toOwnedSlice();
        errdefer alloc.free(&instructions);

        self.* = .{
            .alloc = alloc,
            .pattern = pattern,
            .instructions = instructions,
            .group_count = group_count,
        };
        return @ptrCast(self);
    }

    /// Releases the bytecode instruction set and dereferences the internal structure
    pub fn deinit(ptr: *Pattern) void {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
        const alloc = self.alloc;

        for (self.instructions) |*inst| {
            bytecode.deinitInstruction(self.alloc, inst);
        }
        alloc.free(self.instructions);
        self.* = undefined;
        alloc.destroy(self);
    }

    /// Executes the bytecode-compiled pattern to return the first match 
    /// found starting from byte offset `0` (i.e. start of `input` string)
    /// 
    /// Returns `Match` if the compiled pattern succeeds at the start of `input`
    /// 
    /// Returns `null` if no `Match` can be produced from start of `input`
    /// 
    /// Returns 
    /// - `RegrexError.MemoryError` if allocation failed
    /// - `RegrexError.InvalidUnicode` if a broken UTF-8 code point encountered
    pub fn match(ptr: *Pattern, input: []const u8) RegrexError!?Match {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));

        return try vm.execAt(
            self.alloc, 
            input, 
            0, 
            self.group_count, 
            self.instructions
        );
    }

    /// Executes the bytecode-compiled pattern to search for the first position 
    /// in the `input` where a `Match` can be produced.
    /// 
    /// Returns the first `Match` produced at any position 
    /// 
    /// Returns `null` if no `Match` can be produced anywhere in `input`
    /// 
    /// Returns 
    /// - `RegrexError.MemoryError` if allocation failed
    /// - `RegrexError.InvalidUnicode` if a broken UTF-8 code point encountered
    pub fn search(ptr: *Pattern, input: []const u8) RegrexError!?Match {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
        var pos: usize = 0;

        while (pos <= input.len) {
            if (try vm.execAt(
                self.alloc, 
                input, 
                pos, 
                self.group_count, 
                self.instructions
            )) |m| return m;

            const rune = try Rune.from(input[pos]) catch break;
            pos += rune.len;
        }
        return null;
    }

    /// Creates an interface for `vm.execAt` to be called from inside the `FindGenerator`
    /// while being within current `Pattern` context
    fn execAdapter(
        ptr: *const Pattern,
        input: []const u8, 
        pos: usize
    ) RegrexError!?Match {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));

        return try vm.execAt(
            self.alloc, 
            input, 
            pos, 
            self.group_count, 
            self.instructions
        );
    }

    /// Creates a lazy iterator over all non-overlapping matches in `input` string.
    /// 
    /// Does not scan the input immediately - initializes a `FindIterator` instead.
    /// Matching is performed one item at a time when `FindIterator.next` is called.
    /// 
    /// Returns `FindIterator`
    pub fn findIter(ptr: *Pattern, input: []const u8) RegrexError!FindIterator {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));

        return try FindIterator.init(
            self.alloc,
            input,
            self,
            execAdapter,
        );
    }

    /// Executes the bytecode-compiled pattern to search for 
    /// all non-overlapping matches in `input` string.
    /// 
    /// An 'eager' counterpart to `findIter`. Consumes a `FindIterator`
    /// until it is exhausted and stores every returned match
    /// 
    /// Returns a managed wrapper over `ArrayList(Match)`. The caller must release it
    /// 
    /// Returns 
    /// - `RegrexError.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `RegrexError.InvalidUnicode` if a broken UTF-8 code point encountered
    pub fn findAll(ptr: *Pattern, input: []const u8) RegrexError!MatchListBuffer {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
    
        var iter = try findIter(ptr, input);
        defer iter.deinit();

        var matches = try MatchListBuffer.init(self.alloc, null);
        defer matches.deinit();

        while (try iter.next()) |m| try matches.append(m);

        return matches;
    }

    /// Executes the bytecode-compiled pattern to retrieve all of the matches 
    /// in the `input` string and return its copy with matches  replaced by `repl`.
    /// 
    /// The replacement is literal. Current implementation does not support 
    /// expanding capture group references like `\1` or `$1` and flags like 'ignore case'.
    /// 
    /// `count` argument controls the number of occurences to replace. 
    /// - If `count = 0`, replaces all of the occurences;
    /// - If `count > 0` replaces number of the occurences specified
    /// - If `count` is bigger than the actual occurences count, replaces all and safely ignores rest
    /// 
    /// Returns an allocator-owned copy of the input string (must be freed manually with `alloc.free`).
    /// 
    /// Returns 
    /// - `RegrexError.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `RegrexError.InvalidUnicode` (propagated by `VM.execAt` or encountered during lookup)
    pub fn sub(ptr: *Pattern, input: []const u8, repl: []const u8, opts: SubOptions) RegrexError![]u8 {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
        const count: usize = opts.count orelse 0;

        var out_buf = try DynamicStringBuffer.init(self.alloc, null);
        defer out_buf.deinit();

        var iter = try findIter(ptr, input);
        defer iter.deinit();

        var copy_pos: usize = 0;
        var repl_count: usize = 0;

        while(count == 0 or count > repl_count) {
            const found = (try iter.next()) orelse break;

            var matched = found;
            defer matched.deinit(self.alloc);

            const start = try matched.start(0);
            const end = try matched.end(0);
            const next_pos = iter.nextPos();

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
