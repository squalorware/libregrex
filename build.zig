const std = @import("std");
const Step = std.Build.Step;
const OsTag = std.Target.Os.Tag;
const InstallOptions = Step.InstallArtifact.Options;

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
    ) orelse .dynamic;

    // Root module for Zig package
    _ = b.addModule("regrex", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Skip creating pkg-config file for Windows
    const OS = target.result.os.tag;

    if (OS != .windows) {
        const pkg: *Step.InstallFile = pkg: {
            const file = b.addWriteFile(
                "regrex.pc",
                \\prefix=${pcfiledir}/../..
                \\includedir=${prefix}/include
                \\libdir=${prefix}/lib
                \\
                \\Name: regrex
                \\URL: https://github.com/squalorware/libregrex
                \\Description: A simple Zig implementation of PCRE/Python-inspired regular expression engine.
                \\Version: 0.1.0
                \\Cflags: -I${includedir}
                \\Libs: -L${libdir} -lregrex
            );
            break :pkg b.addInstallFile(
                file.getDirectory().path(b,"regrex.pc"),
                "share/pkgconfig/regrex.pc",
            );
        };

        b.getInstallStep().dependOn(&pkg.step);
    }

    // Build and run unit tests
    const testing_step = b.step("test", "Run unit tests");

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const test_exe = b.addTest(.{
        .root_module = test_mod,
    });
    testing_step.dependOn(&b.addRunArtifact(test_exe).step);

    // Build docs for package
    const docs_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .link_libc = true,
    });

    const docs_obj = b.addObject(.{
        .name = "root",
        .root_module = docs_mod, 
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // Compile library (C-compatible)
    //
    // Default linkage is dynamic, can be changed with build options, 
    // e.g. `-Dlinkage=static`. Option `both` links and compiles both types
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
            .dynamic,
        );
        b.installArtifact(dynamic_lib);
    }
}

/// Compiles the library and includes a C header file
/// 
/// Links `libc` for both statically and dynamically linked libraries
fn buildLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode
) *Step.Compile {
    const zon = @import("./build.zig.zon");
    const version = std.SemanticVersion.parse(zon.version) catch @panic("Invalid semver format");

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
        .version = version,
    });

    lib.installHeader(b.path("include/regrex.h"), "regrex.h");

    return lib;
}

/// Returns a custom output path for non-Windows platforms
fn getTargetOSInstallOptions(target_os: OsTag) InstallOptions  {
    if (target_os != .windows) {
        return .{
           .dest_dir = .{ .override = .prefix },
        };
    }
    return .{};
}
