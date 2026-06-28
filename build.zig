const std = @import("std");
const Step = std.Build.Step;

const LibLinkageMode = enum {
    static,
    dynamic,
    both,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        LibLinkageMode,
        "linkage",
        "Library linkage type: static, dynamic or both",
    ) orelse .static;

    // Zig package module
    _ = b.addModule("regrex", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // C header file
    const header = b.addInstallFileWithDir(
        b.path("include/regrex.h"),
        .header,
        "regrex.h"
    );

    const pkg: *Step.InstallFile = pkg: {
        const file = b.addWriteFile(
            "regrex.pc",
            \\prefix=${pcfiledir}/../..
            \\includedir=${prefix}/include
            \\libdir=${prefix}/lib
            \\
            \\Name: regrex
            \\URL: https://github.com/squalorware/libregrex
            \\Description: An amateurish implementation of regular expressions in Zig.
            \\Version: 0.1.0
            \\Cflags: -I${includedir}
            \\Libs: -L${libdir} -lregrex
        );
        break :pkg b.addInstallFileWithDir(
            file.getDirectory().path(b,"regrex.pc"),
            .prefix,
            "share/pkgconfig/regrex.pc",
        );
    };

    b.getInstallStep().dependOn(&header.step);
    b.getInstallStep().dependOn(&pkg.step);


    // C ABI library 
    //
    // Linkage type is build option, e.g. `-Dlinkage=static`
    if (linkage == .static or linkage == .both) {
        const static_lib = buildLibrary(
            b,
            target,
            optimize,
            .static,
        );
        b.installArtifact(static_lib);
    }

    if (linkage == .dynamic or linkage == .both) {
        const dynamic_lib = buildLibrary(
            b,
            target,
            optimize,
            .dynamic
        );
        b.installArtifact(dynamic_lib);
    }

    // Unit tests
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

    // Documentation generation
    const docs_obj = b.addObject(.{
        .name = "regrex-docs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
        }),
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}

fn buildLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
) *Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/clib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const lib = b.addLibrary(.{
        .name = "regrex",
        .linkage = linkage,
        .root_module = mod,
    });

    return lib;
}
