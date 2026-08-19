const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");
const Match = types.Match;
const RegrexError = types.Error;

pub const ExecContextFn = *const fn(
    ctx: *const anyopaque,
    input: []const u8,
    pos: usize,
) RegrexError!?Match;

/// Lazy iterator over non-overlapping matches in an input string.
///
/// `FindIterator` borrows compiled bytecode and the input buffer. It does not
/// precompute or store all matches. Each call to `next()` resumes scanning from
/// the current byte position and runs the VM only until the next match is found.
pub const FindIterator = @This();

alloc: std.mem.Allocator,
ctx: *const anyopaque,
func: ExecContextFn,
input: []const u8,
pos: usize = 0,
done: bool = false,

// alloc: std.mem.Allocator,
// input: []const u8,
// ctx: *const anyopaque,
// func: ExecContextFn,
// pos: usize = 0,
// done: bool = false,

pub fn init(
    alloc: std.mem.Allocator,
    ctx: *const anyopaque,
    input: []const u8,
    func: ExecContextFn,
) FindIterator {
    return .{
        .alloc = alloc,
        .ctx = ctx,
        .func = func,
        .input = input,
    };
}

pub fn deinit(self: *FindIterator) void {
    self.* = undefined;
}

fn advanceAfterEmptyMatch(self: *FindIterator) RegrexError!void {
    if (!try unicode.nextPos(self.input, &self.pos)) {
        self.done = true;
    }
}

/// Resume scanning from the iterator's current byte position.
///
/// Returns a non-overlappping `Match` if one is found; then the iterator
/// advances to the end of this match. If zero-length Match is encountered,
/// the iterator advances by one UTF-8 code point to avoid infinite loop
///
/// Returns
/// - `Error.MemoryError` if allocation failed
/// - `Error.InvalidUnicode`
///     (propagated by `VM.execAt` or encountered during lookup)
pub fn next(self: *FindIterator) RegrexError!?Match {
    if (self.done) return null;

    while (!self.done) {
        const maybe_match = try self.func(
            self.ctx,
            self.input,
            self.pos,
        );
        if (maybe_match) |found| {
            var match = found;
            errdefer match.deinit(self.alloc);

            const start = try match.start(0);
            const end = try match.end(0);
                
            if (end > start) {    
                self.pos = end;
            } else {
                self.advanceAfterEmptyMatch() catch |err| {
                    var owned = match;
                    owned.deinit(self.alloc);
                    return err;
                };
            }

            return match;
        }
        if (!try unicode.nextPos(self.input, &self.pos)) {
            self.done = true;
            return null;
        }
    }

    self.done = true;
    return null;
}

/// Returns the position from which the next scan will resume.
///
/// After a successful `next()`:
/// - for a non-empty match, this equals the match end;
/// - for an empty match, this points after the code point skipped for progress;
/// - for an empty match at end-of-input, this equals `input.len`.
pub fn resumePos(self: *const FindIterator) usize {
    return self.pos;
}
