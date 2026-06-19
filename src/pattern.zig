//! A representation of a regular expression pattern compiled to bytecode instructions
//! 
//! Defines a public `Pattern` exported by Regrex API. `Pattern` is 
//! an opaque type which encapsulates a heap-allocated `CompilePattern` object
//! which stores the compiled bytecode instructions, a number of capturing groups 
//! and the original pattern string.
//! 
//! `CompiledPattern` is intentionally hidden behind `Pattern` to prevent manipulations
//! with the compiled bytecode. `Pattern` exposes a set of methods that wrap over respective
//! VM functions, allowing end user interaction without exposing the bytecode directly.
const std = @import("std");
const RegrexError = @import("./common/errors.zig").RegrexError;
const Instruction = @import("./core/icr.zig").Instruction;
const Match = @import("./Match.zig");
const VM = @import("vm.zig");


pub const SubOptions = @import("./common/types.zig").SubOptions;
/// Frees compiled bytecode buffer and any owned data
/// stored inside instructions.
/// 
/// Character class instructions own duplicated 
/// `ranges` and `chars` slices and must be released
/// before the bytecode slice itself is freed.
pub fn freeCompiledBuffer(
    alloc: std.mem.Allocator, 
    bytecode: []Instruction
) void {
    for (bytecode) |inst| {
        switch(inst) {
            .Class => |cls| {
                alloc.free(cls.ranges);
                alloc.free(cls.chars);
            },
            else => {},
        }
    }

    alloc.free(bytecode);
}

/// Internal representation of a compiled regular expression pattern.
/// 
/// It is deliberatly unavailable from outside to prevent any malicious access.
/// Users can interact with it only through opaque top-level `Pattern` type. 
const CompiledPattern = struct {
    /// Allocator that owns thsi compiled pattern and its bytecode
    alloc: std.mem.Allocator,
    /// Bytecode instructions buffer
    bytecode: []Instruction,
    /// Number of groups returned by the pattern, excluding group 0
    group_count: usize,
    /// Original pattern string (borrowed, not owned by allocator)
    pattern: []const u8,
};

/// Opaque type to secure the internal CompiledPattern representation.
/// 
/// Ensures full encapsulation and exposes outside only a specific set of operations
/// without giving access to the compiled bytecode buffer itself
pub const Pattern = opaque {
    /// Consumes bytecode produced by compiler taking ownership over it
    /// and creates an opaque public handle for internal `CompiledPattern` representation.
    pub fn init(
        alloc: std.mem.Allocator,
        group_count: usize,
        opcodes: []Instruction,
        pattern: []const u8,
    ) RegrexError!*Pattern {
        const self = alloc.create(CompiledPattern) catch {
            return RegrexError.MemoryError;
        };
        self.* = .{
            .alloc = alloc,
            .bytecode = opcodes,
            .group_count = group_count,
            .pattern = pattern,
        };
        return @ptrCast(self);
    }

    /// Destroys the compiled pattern and releases the bytecode buffer.
    /// 
    /// The pointer must be created by the `Pattern.init` using the same allocator
    /// which is stored in the internal `CompiledPattern` object.
    pub fn deinit(ptr: *Pattern) void {
        const self: *CompiledPattern = @ptrCast(@alignCast(ptr));
        const alloc = self.alloc;

        freeCompiledBuffer(alloc, self.bytecode);

        self.* = undefined;
        alloc.destroy(self);
    }

    /// Scans `input` string and returns the first Match 
    /// of this pattern it has encountered at any position.
    /// 
    /// Returns a `Match` object on success
    /// 
    /// Returns `null` if no match found
    /// 
    /// Returns 
    /// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `Error.InvalidUnicode` if a broken UTF-8 code point was encountered
    pub fn search(ptr: *const Pattern, input: []const u8) RegrexError!?Match {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.search(
            self.alloc,
            self.bytecode,
            self.group_count,
            input,
        );
    }

    /// Matches this pattern against the beginning of the `input` string.
    /// 
    /// Returns a `Match` object if a Match was found at the `input` start
    /// 
    /// Returns `null` if no match found or match was not at the beginning.
    /// 
    /// Returns 
    /// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `Error.InvalidUnicode` if a broken UTF-8 code point was encountered
    pub fn match(ptr: *const Pattern, input: []const u8) RegrexError!?Match {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.match(
            self.alloc,
            self.bytecode,
            self.group_count,
            input,
        );
    }

    /// Creates an instance of a lazy `FindIterator`.
    /// 
    /// Does not per\form an eager scan of the whole input - matches lazily
    /// one input at a time instead. Does not advance until `FindIterator.next`
    /// is called explicitly.
    /// 
    /// Should not be exposed at root level due to ownership complications
    /// 
    /// Returns `FindIterator` instance
    pub fn findIter(ptr: *const Pattern, input: []const u8) VM.FindIterator {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.findIter(
            self.alloc,
            self.bytecode,
            self.group_count,
            input,
        );
    }

    /// Retrieves eagerly all non-overlapping matches of this pattern found 
    /// in the `input` string.
    /// 
    /// Returns a slice of `Match` objects in case of success. 
    /// This slice is allocator-owned and must be released; `Match` items
    /// it contains may also own captured data and must be released individually.
    /// 
    /// Returns 
    /// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `Error.InvalidUnicode` if a broken UTF-8 code point was encountered
    pub fn findAll(ptr: *const Pattern, input: []const u8) RegrexError![]Match {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.findAll(
            self.alloc,
            self.bytecode,
            self.group_count,
            input,
        );
    }

    /// Creates a copy of the `input` string and replaces match occurences.
    /// 
    /// The number of replacements is controlled by `options.count`
    /// - If `options.count == 0` replace all occurences (default value);
    /// - If `options.count > 0` replace exactly `options.count` times;
    /// - If `options.count` is greater than matches count, replace all and safely ignore rest
    /// 
    /// Returns an allocated string buffer containing a modified copy of `input` on success
    /// 
    /// Returns 
    /// - `Error.MemoryError` if failed allocating or manipulating the copy buffer
    /// - `Error.InvalidUnicode` if a broken UTF-8 code point was encountered
    pub fn sub(
        ptr: *const Pattern,
        repl: []const u8, 
        input: []const u8, 
        options: SubOptions,
    ) ![]u8 {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.sub(
            self.alloc,
            self.bytecode,
            self.group_count,
            repl,
            input,
            options.count,
        );
    }
};

const testing = std.testing;

/// Returns a fixture providing an allocator-owned buffer of bytecode instructions.
fn bytecodeFixture(alloc: std.mem.Allocator) ![]Instruction {
    return try alloc.dupe(Instruction, &[_]Instruction {
        .{ .Save = 0 },
        .{ .Rune = '4' },
        .{ .Rune = '2' },
        .{ .Rune = '0' },
        .{ .Save = 1 },
        .Match,
    });
}

test "Pattern.match() should return the first `Match` at the input start" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420"
    );
    defer pattern.deinit();

    var result = (try pattern.match("420 kek")) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.full());
    try testing.expectEqual(@as(usize, 0), try result.start(0));
    try testing.expectEqual(@as(usize, 3), try result.end(0));
}

test "Pattern.match() should return `null` when no match at the input start" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420",
    );
    defer pattern.deinit();

    const result = try pattern.match("lol 420 kek");

    try testing.expect(result == null);
}

test "Pattern.search() should return the first encountered Match in input" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420",
    );
    defer pattern.deinit();

    var result = (try pattern.search("lol 420 kek")) orelse {
        try testing.expect(false);
        return;
    };
    defer result.deinit(allocator);

    try testing.expectEqualStrings("420", result.full());
    try testing.expectEqual(@as(usize, 4), try result.start(0));
    try testing.expectEqual(@as(usize, 7), try result.end(0));
}

test "Pattern.findIter() should return lazy retrieve non-overlapping matches one at a time" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420",
    );
    defer pattern.deinit();

    var iter = pattern.findIter("420 lol 420 kek");
    defer iter.deinit();

    var first = (try iter.next()) orelse {
        try testing.expect(false);
        return;
    };
    defer first.deinit(allocator);

    try testing.expectEqualStrings("420", first.full());
    try testing.expectEqual(@as(usize, 0), try first.start(0));
    try testing.expectEqual(@as(usize, 3), try first.end(0));

    var second = (try iter.next()) orelse {
        try testing.expect(false);
        return;
    };
    defer second.deinit(allocator);

    try testing.expectEqualStrings("420", second.full());
    try testing.expectEqual(@as(usize, 8), try second.start(0));
    try testing.expectEqual(@as(usize, 11), try second.end(0));

    const third = try iter.next();
    try testing.expect(third == null);
}

test "Pattern.findIter() should return null if no match on next iteration" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420",
    );
    defer pattern.deinit();

    var iter = pattern.findIter("lol kek");
    defer iter.deinit();

    const result = try iter.next();
    try testing.expect(result == null);
}

test "Pattern.findAll() should return all non-overlapping matches" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);
    const expected_matches = [_]struct {
        start: usize,
        end: usize,
    }{
        .{ .start = 0, .end = 3 },
        .{ .start = 8, .end = 11 },
    };

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420"
    );
    defer pattern.deinit();

    const results = try pattern.findAll("420 lol 420 kek");
    defer Match.free(allocator, results);

    for (expected_matches, 0..) |expected, i| {
        try testing.expectEqualStrings("420", results[i].full());
        try testing.expectEqual(expected.start, try results[i].start(0));
        try testing.expectEqual(expected.end, try results[i].end(0));
    }
}

test "Pattern.sub() should return a string with all matched occurences replaced" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420"
    );
    defer pattern.deinit();

    const result = try pattern.sub("67", "420 lol 420 kek", .{});
    defer allocator.free(result);

    try testing.expectEqualStrings("67 lol 67 kek", result);
}

test "Pattern.sub() should only replace an exact number of matches" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420"
    );
    defer pattern.deinit();

    const result = try pattern.sub("67", "420 lol 420 kek", .{ .count = 1 });
    defer allocator.free(result);

    try testing.expectEqualStrings("67 lol 420 kek", result);    
}

test "Pattern.sub() should replace all occurences and safely ignore rest if options.count is greater than actual occurences count" {
    const allocator = testing.allocator;
    const bytecode = try bytecodeFixture(allocator);

    const pattern: *Pattern = try Pattern.init(
        allocator,
        0,
        bytecode,
        "420"
    );
    defer pattern.deinit();

    const result = try pattern.sub("67", "420 lol 420 kek", .{ .count = 67 });
    defer allocator.free(result);

    try testing.expectEqualStrings("67 lol 67 kek", result);    
}
