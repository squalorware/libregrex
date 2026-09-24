const std = @import("std");
const types = @import("types");
const syntax = @import("./syntax.zig");
const ErrorSet = types.errors.ErrorSet;
const T_ManagedArrayList = types.meta.T_ManagedArrayList;

fn freeCharClassCallback(alloc: std.mem.Allocator, ptr: ?*syntax.CharClass) void {
    const cls = ptr orelse return;

    alloc.free(cls.ranges);
    alloc.free(cls.chars);
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

    pub fn free(alloc: std.mem.Allocator, self: CompileOutput) void {
        alloc.free(self.prog);

        for (self.classes) |cls| {
            alloc.free(cls.ranges);
            alloc.free(cls.chars);
        }
        alloc.free(self.classes);
    }
};

pub const CompileBuffers = struct {
    alloc: std.mem.Allocator,
    prog: ByteBuffer,
    classes: CharClassBuffer,
    flags: syntax.Flags,

    pub fn init(alloc: std.mem.Allocator, flags: syntax.Flags) ErrorSet!CompileBuffers {
        return .{
            .alloc = alloc,
            .prog = try ByteBuffer.init(alloc, null),
            .classes = try CharClassBuffer.init(alloc, null),
            .flags = flags,
        };
    }

    pub fn deinit(self: *CompileBuffers) void {
        self.prog.deinit();
        self.classes.deinit();
        self.* = undefined;
    }

    /// Deep-copies a char class into memory owned by compiler to avoid emitted `Instruction` pointing into `Parser` arena
    pub fn cloneCharClass(self: *CompileBuffers, cls: syntax.CharClass) ErrorSet!usize {
        const ranges = self.alloc.dupe(syntax.RuneRange, cls.ranges) catch {
            return ErrorSet.MemoryError;
        };
        errdefer self.alloc.free(ranges);

        const chars = self.alloc.dupe(u21, cls.chars) catch {
            return ErrorSet.MemoryError;
        };
        errdefer self.alloc.free(chars);

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

    // /// Deep-copies a sequence into memory owned by compiler to avoid emitted `Instruction` pointing into `Parser` arena
    // pub fn cloneSequence(self: *CompileBuffers, seq: syntax.Sequence) ErrorSet!syntax.Sequence {
    //     const nodes = self.alloc.dupe(*syntax.Node, seq.nodes) catch {
    //         return ErrorSet.MemoryError;
    //     };
    //     errdefer self.alloc.free(nodes);

    //     return .{ .nodes = nodes };
    // }
};

test "Should deep copy char classes buffer with cloneCharClass" {
    const allocator = std.testing.allocator;

    var state = try CompileBuffers.init(allocator, .{});
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
