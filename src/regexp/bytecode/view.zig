const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;
const formatStr = types.formatStr;
const ErrorSet = types.errors.ErrorSet;
const T_Range = types.meta.T_Range;
const Opcode = @import("./opcodes.zig").Opcode;
const Flags = @import("../syntax.zig").Flags;

pub fn FieldView(comptime T: type) type {
    return struct {
        value: T,
    };
}

pub const InstructionRange = T_Range(usize, .{});

pub fn InstructionView(comptime OT: type) type {
    return struct {
        const Self = @This();
        gpa: std.mem.Allocator,
        inst: []const u8,
        start: usize,
        end: usize,
        opcode: FieldView(Opcode),
        flags: ?FieldView(Flags),
        operands: ?[]FieldView(OT),

        pub fn init(gpa: Allocator, buf: []const u8, op: Opcode, mod: ?Flags, data: ?[]OT, addr: InstructionRange) ErrorSet!Self {
            const flags: ?FieldView(Flags) = if (mod) |f|
                .{ .value = f }
            else
                null;

            const ops: ?[]FieldView(OT) = if (data) |items| blk: {
                const views = try gpa.alloc(FieldView(OT), items.len);

                for (items, views) |item, *view| {
                    view.* = .{ .value = item };
                }
                break :blk views;
            } else null;

            return .{
                .gpa = gpa,
                .inst = buf,
                .start = addr.start,
                .end = addr.end,
                .opcode = .{
                    .value = op,
                },
                .flags = flags,
                .operands = ops,
            };
        }

        pub fn deinit(self: *Self) void {
            const gpa = self.gpa;

            if (self.operands) |ops| {
                gpa.free(ops);
            }

            self.* = undefined;
        }

        // pub fn repr(self: Self) ErrorSet!u8 {
        //     var buffer = try types.StringBuffer.init(self.gpa, null);
        //     errdefer buffer.deinit();

        //     try buffer.appendFmt("")
        // }
    };
}
// pub fn Instruction(comptime T: type, comptime op: OpCode, flags: ?syntax.Flags, data: ?T) type {
//     return struct {
//         opcode: OpCode = op,
//         opmode: ?syntax.Flags = flags,
//         opvals: ?T = data,
//     };
// }
