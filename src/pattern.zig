//! Compiled regular expression pattern representation.
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
const Instruction = @import("./core/icr.zig").Instruction;
const Match = @import("./Match.zig");
const VM = @import("vm.zig");

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
    ) !*Pattern {
        const self = try alloc.create(CompiledPattern);
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
    /// Returns `Error` if allocation failed or encountered invalid Unicode 
    pub fn search(ptr: *const Pattern, input: []const u8) !?Match {
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
    /// Returns `Error` if allocation failed or encountered invalid Unicode 
    pub fn match(ptr: *const Pattern, input: []const u8) !?Match {
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
    /// Does not perform an eager scan of the whole input - matches lazily
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
    /// Returns `Error` if allocation failed or if VM encountered an unrecoverable error.
    pub fn findAll(ptr: *const Pattern, input: []const u8) ![]Match {
        const self: *const CompiledPattern = @ptrCast(@alignCast(ptr));
        return VM.findAll(
            self.alloc,
            self.bytecode,
            self.group_count,
            input,
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

test "Should return a `Match` from input start by Pattern.match" {
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

    try testing.expectEqualStrings("420", result.str());
    try testing.expectEqual(@as(usize, 0), result.span.start);
    try testing.expectEqual(@as(usize, 3), result.span.end);
}

test "Should return `null` when no match at input start by Pattern.match" {
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

test "Should return first Match from input by Pattern.search" {
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

    try testing.expectEqualStrings("420", result.str());
    try testing.expectEqual(@as(usize, 4), result.span.start);
    try testing.expectEqual(@as(usize, 7), result.span.end);
}

test "Should return lazy non-overlapping match by Pattern.findIter" {
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
    try testing.expectEqualStrings("420", first.str());
    try testing.expectEqual(@as(usize, 0), first.span.start);
    try testing.expectEqual(@as(usize, 3), first.span.end);

    var second = (try iter.next()) orelse {
        try testing.expect(false);
        return;
    };
    try testing.expectEqualStrings("420", second.str());
    try testing.expectEqual(@as(usize, 8), second.span.start);
    try testing.expectEqual(@as(usize, 11), second.span.end);

    const third = try iter.next();
    try testing.expect(third == null);
}

test "Should return null by Pattern.findIter if no match" {
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

test "Should return all non-overlapping matches by Pattern.findAll" {
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
        try testing.expectEqualStrings("420", results[i].str());
        try testing.expectEqual(expected.start, results[i].span.start);
        try testing.expectEqual(expected.end, results[i].span.end);
    }
}
