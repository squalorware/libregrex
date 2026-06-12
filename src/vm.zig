const std = @import("std");
const AST = @import("./core/ast.zig");
const Error = @import("./common/errors.zig").Error;
const Instruction = @import("./core/icr.zig").Instruction;
const Match = @import("./Match.zig");
const types = @import("./common/types.zig");
const utils = @import("./common/utils.zig");

const DecodedRune = types.DecodedRune;
const Rune = types.Rune;
const Span = types.Span;
const VmError = Error || std.mem.Allocator.Error;

const Frame = struct {
    pc: usize,
    pos: usize,
    captures: []?usize,

    fn deinit(self: *Frame, alloc: std.mem.Allocator) void {
        alloc.free(self.captures);
        self.* = undefined;
    }
};

const RuneMatcher = union(enum) {
    any,
    exact: Rune,
    class: AST.CharClass,
};

fn restoreFromStack(
    alloc: std.mem.Allocator,
    stack: *std.ArrayList(Frame),
    captures: *[]?usize,
    pc: *usize,
    pos: *usize,
) bool {
    const frame = stack.pop() orelse return false;

    alloc.free(captures.*);

    pc.* = frame.pc;
    pos.* = frame.pos;
    captures.* = frame.captures;

    return true;
}

fn recoverOrFail(
    alloc: std.mem.Allocator,
    stack: *std.ArrayList(Frame),
    captures: *[]?usize,
    pc: *usize,
    pos: *usize,
) bool {
    if (restoreFromStack(alloc, stack, captures, pc, pos)) {
        return true;
    }
    alloc.free(captures.*);
    return false;
}

fn cloneCaptures(
    alloc: std.mem.Allocator,
    captures: []const ?usize,
) VmError![]?usize {
    return try alloc.dupe(?usize, captures);
}

fn runeInClass(rune: Rune, cls: AST.CharClass) bool {
    var matched = false;

    for (cls.ranges) |range| {
        if (rune >= range.start and rune <= range.end) {
            matched = true;
            break;
        }
    }

    if (!matched) {
        for (cls.chars) |char| {
            if (rune == char) {
                matched = true;
                break;
            }
        }
    }
    return if (cls.negated) !matched else matched;
}

fn runeMatches(rune: Rune, matcher: RuneMatcher) bool {
    return switch(matcher) {
        .any => true,
        .exact => |expected| rune == expected,
        .class => |cls| runeInClass(rune, cls),
    };
}

fn consumeRune(
    input: []const u8,
    pos: *usize,
    matcher: RuneMatcher,
) VmError!bool {
    const decoded = try utils.decodeRuneAt(input, pos.*) orelse {
        return false;
    };
    if (!runeMatches(decoded.rune, matcher)) {
        return false;
    }
    pos.* += decoded.len;
    return true;
}

fn makeMatch(
    allocator: std.mem.Allocator,
    input: []const u8,
    group_count: usize,
    captures: []const ?usize,
) VmError!Match {
    const start = captures[0] orelse 0;
    const end = captures[1] orelse start;

    var groups = try allocator.alloc(?Span, group_count);
    errdefer allocator.free(groups);

    var group_idx: usize = 0;
    while (group_idx < group_count) : (group_idx += 1) {
        const start_slot = (group_idx + 1) * 2;
        const end_slot = start_slot + 1;

        const group_start = captures[start_slot] orelse {
            groups[group_idx] = null;
            continue;
        };
        const group_end = captures[end_slot] orelse {
            groups[group_idx] = null;
            continue;
        };

        groups[group_idx] = .{
            .start = group_start,
            .end = group_end,
        };
    }
    return .{
        .input = input,
        .span = .{
            .start = start,
            .end = end,
        },
        .groups = groups,
    };
}

pub fn execAt(
    allocator: std.mem.Allocator,
    bytecode: []const Instruction,
    group_count: usize,
    input: []const u8,
    start_pos: usize,
) VmError!?Match {
    const capture_slots = (group_count + 1) * 2;

    var captures = try allocator.alloc(?usize, capture_slots);
    errdefer allocator.free(captures);

    for (captures) |*slot| {
        slot.* = null;
    }

    var stack = std.ArrayList(Frame).empty;
    defer {
        for (stack.items) |*frame| {
            frame.deinit(allocator);
        }
        stack.deinit(allocator);
    }

    var pc: usize = 0;
    var pos: usize = start_pos;

    while (true) {
        if (pc >= bytecode.len) {
            if (recoverOrFail(allocator, &stack, &captures, &pc, &pos)) {
                continue;
            }
            return null;
        }
        const inst = bytecode[pc];
        switch (inst) {
            .Rune => |expected| {
                if (try consumeRune(input, &pos, .{ .exact = expected})) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(
                    allocator, 
                    &stack, 
                    &captures, 
                    &pc, 
                    &pos
                )) continue;
                return null;
            },
            .Any => {
                if (try consumeRune(input, &pos, .any)) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(
                    allocator, 
                    &stack, 
                    &captures, 
                    &pc, 
                    &pos
                )) continue;
                return null;                
            },
            .Class => |cls| {
                if (try consumeRune(input, &pos, .{ .class = cls})) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(
                    allocator, 
                    &stack, 
                    &captures, 
                    &pc, 
                    &pos
                )) continue;
                return null;
            },
            .AssertStart => {
                if (pos == 0) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(
                    allocator, 
                    &stack, 
                    &captures, 
                    &pc, 
                    &pos
                )) continue;
                return null;
            },
            .AssertEnd => {
                if (pos == input.len) {
                    pc += 1;
                    continue;
                }
                if (recoverOrFail(
                    allocator, 
                    &stack, 
                    &captures, 
                    &pc, 
                    &pos
                )) continue;
                return null;
            },
            .Save => |slot| {
                if (slot >= captures.len) {
                    if (recoverOrFail(
                        allocator, 
                        &stack, 
                        &captures, 
                        &pc, 
                        &pos
                    )) continue;

                    return null;     
                }
                captures[slot] = pos;
                pc += 1;
            },
            .Split => |split| {
                const alt_captures = try cloneCaptures(allocator, captures);

                try stack.append(allocator, .{
                    .pc = split.second,
                    .pos = pos,
                    .captures = alt_captures,
                });
                pc = split.first;
            },
            .Jump => |target| {
                pc = target;
            },
            .Match => {
                const result = try makeMatch(
                    allocator,
                    input,
                    group_count,
                    captures,
                );
                allocator.free(captures);
                return result;
            },
        }
    }
}
