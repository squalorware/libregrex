const std = @import("std");
const types = @import("types");
const advanceOneRune = @import("./syntax.zig").advanceOneRune;
const Match = types.matching.Match;
const RegrexError = types.Error;

pub const ExecContextFn = *const fn(
    alloc: std.mem.Allocator,
    input: []const u8,
    ctx: *const anyopaque,
    pos: usize,
) RegrexError!?Match;

/// Lazy iterator over non-overlapping matches in an input string.
///
/// `FindIterator` borrows compiled bytecode and the input buffer. It does not
/// precompute or store all matches. Each call to `next()` resumes scanning from
/// the current byte position and runs the VM only until the next match is found.
pub const Self = @This();

alloc: std.mem.Allocator,
input: []const u8,
ctx: *const anyopaque,
func: ExecContextFn,
pos: usize = 0,
done: bool = false,

pub fn init(
    alloc: std.mem.Allocator,
    input: []const u8,
    ctx: *const anyopaque,
    func: ExecContextFn,
) Self {
    return .{
        .alloc = alloc,
        .input = input,
        .ctx = ctx,
        .func = func,
    };
}

fn advanceAfterEmptyMatch(self: *Self) RegrexError!void {
    if (!try advanceOneRune(self.input, self.pos, null)) {
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
pub fn next(self: *Self) RegrexError!?Match {
    if (self.done) return null;

    while (self.pos <= self.input.len) {
        const maybe_match = try self.func(
            self.alloc,
            self.input,
            self.ctx,
            self.pos
        );
        if (maybe_match) |match| {
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
        if (!try advanceOneRune(self.input, self.pos, null)) {
            self.done = true;

            return null;
        }
    }

    self.done = true;
    return null;
}