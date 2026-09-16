const std = @import("std");
const types = @import("types");
const unicode = @import("unicode");
const ExecutionContext = @import("./VM.zig").ExecutionContext;
const Match = types.Match;
const ErrorSet = types.errors.ErrorSet;
const T_Closure = types.meta.T_Closure;

/// Iterator state representation. Shares context with compiled Pattern
const _Iterator = struct {
    ctx: *const anyopaque,
    done: bool = false,
    func: T_Closure(anyopaque, ExecutionContext, ?Match),
    input: []const u8,
    pos: usize = 0,
};

/// Public-facing Iterator interface
///
/// On init takes a pointer and a closure function from `Pattern`,
/// which allows updating shared execution context and call VM execution within closure
pub const LazyIterator = opaque {
    pub fn init(
        alloc: std.mem.Allocator,
        ctx: *const anyopaque,
        input: []const u8,
        func: T_Closure(anyopaque, ExecutionContext, ?Match),
    ) ErrorSet!*LazyIterator {
        const self: *_Iterator = alloc.create(_Iterator) catch {
            return ErrorSet.MemoryError;
        };
        self.* = .{
            .ctx = ctx,
            .func = func,
            .input = input,
        };
        return @ptrCast(self);
    }

    pub fn deinit(ptr: *LazyIterator, alloc: std.mem.Allocator) void {
        const self: *_Iterator = @ptrCast(@alignCast(ptr));

        self.* = undefined;
        alloc.destroy(self);
    }

    fn advanceAfterEmptyMatch(ptr: *LazyIterator) ErrorSet!void {
        const self: *_Iterator = @ptrCast(@alignCast(ptr));

        if (!try unicode.advancePos(self.input, &self.pos)) {
            self.done = true;
        }
    }

    /// Scans the input once, starting at position in current context,
    /// then advances position register by one UTF-8 codepoint bytelength
    pub fn next(ptr: *LazyIterator) ErrorSet!?Match {
        const self: *_Iterator = @ptrCast(@alignCast(ptr));

        if (self.done) return null;

        while (!self.done) {
            const maybe_match = try self.func(self.ctx, .{ .input = self.input, .pos = self.pos });

            if (maybe_match) |found| {
                var match = found;
                errdefer match.deinit();

                const start = try match.start(0);
                const end = try match.end(0);

                if (end > start) {
                    self.pos = end;
                } else {
                    ptr.advanceAfterEmptyMatch() catch |err| {
                        var owned = match;
                        owned.deinit();
                        return err;
                    };
                }

                return match;
            }
            if (!try unicode.advancePos(self.input, &self.pos)) {
                self.done = true;
                return null;
            }
        }
        self.done = true;
        return null;
    }

    /// Position in input from which the next iteration will resume lookup
    pub fn resumePos(ptr: *LazyIterator) usize {
        const self: *_Iterator = @ptrCast(@alignCast(ptr));
        return self.pos;
    }
};
