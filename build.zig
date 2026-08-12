const std = @import("std");
const Step = std.Build.Step;
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

    const types_mod = b.addModule("types", .{
        .root_source_file = b.path("src/types/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unicode_mod = b.addModule("unicode", .{
        .root_source_file = b.path("src/unicode/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    unicode_mod.addImport("types", types_mod);

    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("src/engine/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    engine_mod.addImport("types", types_mod);
    engine_mod.addImport("unicode", unicode_mod);

    // Root module for Zig package
    const root_mod = b.addModule("regrex", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "types", .module = types_mod },
            .{ .name = "unicode", .module = unicode_mod },
            .{ .name = "engine", .module = engine_mod },
        }
    });

    // Skip creating pkg-config file for Windows
    const OS = target.result.os.tag;

    if (OS != .windows) {
        const pkg: *Step.InstallFile = pkg: {
            const file = b.addWriteFile("regrex.pc",
                \\prefix=${pcfiledir}/../..
                \\includedir=${prefix}/include
                \\libdir=${prefix}/lib
                \\
                \\Name: regrex
                \\URL: https://github.com/squalorware/libregrex
                \\Description: A simple Zig implementation of PCRE/Python-inspired regular expression engine.
                \\Version: 0.1.1
                \\Cflags: -I${includedir}
                \\Libs: -L${libdir} -lregrex
            );
            break :pkg b.addInstallFile(
                file.getDirectory().path(b, "regrex.pc"),
                "share/pkgconfig/regrex.pc",
            );
        };

        b.getInstallStep().dependOn(&pkg.step);
    }

    // Build and run unit tests
    const root_unit_tests = b.addTest(.{
        .name = "regrex",
        .root_module = root_mod,
    });
    const types_unit_tests = b.addTest(.{
        .name = "types",
        .root_module = types_mod,
    });
    const engine_unit_tests = b.addTest(.{
        .name = "engine",
        .root_module = engine_mod,
    });
    const unicode_unit_tests = b.addTest(.{
        .name = "unicode",
        .root_module = unicode_mod,
    });

    const unit_test_step = b.step("test", "Run unit tests");

    unit_test_step.dependOn(&b.addRunArtifact(root_unit_tests).step);
    unit_test_step.dependOn(&b.addRunArtifact(types_unit_tests).step);
    unit_test_step.dependOn(&b.addRunArtifact(unicode_unit_tests).step);
    unit_test_step.dependOn(&b.addRunArtifact(engine_unit_tests).step);

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
            root_mod,
        );
        b.installArtifact(static_lib);
    }

    if (linkage == .dynamic or linkage == .both) {
        const dynamic_lib = buildLibrary(
            b,
            target,
            optimize,
            .dynamic,
            root_mod,
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
    linkage: std.builtin.LinkMode,
    root_mod: *std.Build.Module,
) *Step.Compile {
    const zon = @import("./build.zig.zon");
    const version = std.SemanticVersion.parse(zon.version) catch {
        @panic("Invalid semver format");
    };

    const mod = b.createModule(.{
        .root_source_file = b.path("src/clib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addImport("regrex", root_mod);

    const lib = b.addLibrary(.{
        .name = "regrex",
        .linkage = linkage,
        .root_module = mod,
        .version = version,
    });

    lib.installHeader(b.path("include/regrex.h"), "regrex.h");

    return lib;
}
