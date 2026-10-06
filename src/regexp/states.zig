const std = @import("std");
const types = @import("types");
const syntax = @import("./syntax.zig");
const ErrorSet = types.errors.ErrorSet;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;

fn freeCharClassCallback(gpa: std.mem.Allocator, ptr: *syntax.CharClass) void {
    ptr.deinit(gpa);
}

pub const ByteBuffer = T_ManagedArrayList(u8, null);
pub const CharClassBuffer = T_ManagedArrayList(syntax.CharClass, freeCharClassCallback);

pub const ParserOutput = struct {
    syntax_tree: *syntax.Node,
    inline_flags: syntax.Flags,
    captures_count: usize,
};

pub const CompileOutput = struct {
    prog: []u8,
    classes: []syntax.CharClass,
    captures_count: usize,

    pub fn free(self: *CompileOutput, gpa: std.mem.Allocator) void {
        gpa.free(self.prog);

        syntax.CharClass.freeCharClasses(gpa, self.classes);
        self.* = undefined;
    }
};

pub const CompileStateBuffer = struct {
    gpa: std.mem.Allocator,
    prog: ByteBuffer,
    classes: CharClassBuffer,
    flags: syntax.Flags,

    pub fn init(gpa: std.mem.Allocator, flags: syntax.Flags) ErrorSet!CompileStateBuffer {
        return .{
            .gpa = gpa,
            .prog = try ByteBuffer.init(gpa, null),
            .classes = try CharClassBuffer.init(gpa, null),
            .flags = flags,
        };
    }

    pub fn deinit(self: *CompileStateBuffer) void {
        self.prog.deinit();
        self.classes.deinit();
        self.* = undefined;
    }

    /// Deep-copies a char class into memory owned by compiler to avoid emitted `Instruction` pointing into `Parser` arena
    pub fn cloneCharClass(self: *CompileStateBuffer, cls: syntax.CharClass) ErrorSet!usize {
        const ranges = self.gpa.dupe(syntax.RuneRange, cls.ranges) catch {
            return ErrorSet.MemoryError;
        };
        errdefer self.gpa.free(ranges);

        const chars = self.gpa.dupe(u21, cls.chars) catch {
            return ErrorSet.MemoryError;
        };
        errdefer self.gpa.free(chars);

        const idx: usize = self.classes.len();

        try self.classes.append(.{
            .ranges = ranges,
            .chars = chars,
            .preset = cls.preset,
            .negated_preset = cls.negated_preset,
            .negated = cls.negated,
        });

        return idx;
    }
};

test "Should deep copy char classes buffer with cloneCharClass" {
    const gpa = std.testing.allocator;

    var state = try CompileStateBuffer.init(gpa, .{});
    defer state.deinit();

    const ranges = [_]syntax.RuneRange{.{ .start = 'a', .end = 'z' }};
    const chars = [_]u21{'_'};
    const source: syntax.CharClass = .{
        .ranges = &ranges,
        .chars = &chars,
    };

    const index = try state.cloneCharClass(source);
    const cloned = state.classes.items()[index];

    try std.testing.expectEqual(@as(usize, 0), index);
    try std.testing.expect(cloned.ranges.ptr != source.ranges.ptr);
    try std.testing.expect(cloned.chars.ptr != source.chars.ptr);
    try std.testing.expectEqualDeep(source.ranges, cloned.ranges);
    try std.testing.expectEqualDeep(source.chars, cloned.chars);
}
