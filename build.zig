const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("regrex", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const static_lib: ?*Step.Compile = lib: {
        const static_lib = b.addLibrary(.{
            .linkage = .static,
            .name = "regrex",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/extern.zig"),
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

    const dynamic_lib: ?*Step.Compile = lib: {
        const dynamic_lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = "regrex",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/extern.zig"),
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

    const pkg: *Step.InstallFile = pkg: {
        const file = b.addWriteFile("regrex.pc", b.fmt(
            \\prefix={s}
            \\includedir=${{prefix}}/include
            \\libdir=${{prefix}}/lib
            \\
            \\Name: regrex
            \\URL: https://github.com/squalorware/libregrex
            \\Description: An amateurish implementation of regular expressions in Zig.
            \\Version: 0.1.0
            \\Cflags: -I${{includedir}}
            \\Libs: -L${{libdir}} -lregrex
        , .{b.install_prefix}));
        break :pkg b.addInstallFileWithDir(
            file.getDirectory().path(b,"regrex.pc"),
            .prefix,
            "share/pkgconfig/regrex.pc",
        );
    };

    if (static_lib) |lib| b.installArtifact(lib);
    if (dynamic_lib) |lib| b.installArtifact(lib);
    b.getInstallStep().dependOn(&header.step);
    b.getInstallStep().dependOn(&pkg.step);

    const testing_step = b.step("test", "Run unit tests");

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_exe = b.addTest(.{
        .root_module = test_mod,
    });
    testing_step.dependOn(&b.addRunArtifact(test_exe).step);
}
