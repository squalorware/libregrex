const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("regrex", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const build_static: ?*Step.Compile = lib: {
        const static_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "regrex",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ext.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        if (target.result.os.tag == .windows) {
            static_lib.root_module.linkSystemLibrary("ws2_32", .{});
        }
        break :lib static_lib;
    };

    const build_dynamic: ?*Step.Compile = lib: {
        const dynamic_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "regrex",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/ext.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        break :lib dynamic_lib;
    };

    const header = b.addInstallFileWithDir(
        b.path("include/regrex.h"),
        .header,
        "regrex.h"
    );

    if (build_static) |lib| b.installArtifact(lib);
    if (build_dynamic) |lib| b.installArtifact(lib);
    b.getInstallStep().dependOn(&header.step);

    const testing_step = b.step("test", "Run unit tests");

    const lexer_test_mod = b.createModule(.{
        .root_source_file = b.path("src/lexer/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = switch (target.result.os.tag) {
            .linux, .macos => true,
            else => null,
        },
    });
    const lexer_test = b.addTest(.{
        .root_module = lexer_test_mod,
    });
    testing_step.dependOn(&b.addRunArtifact(lexer_test).step);
}
