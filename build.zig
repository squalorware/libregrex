const std = @import("std");
const Import = std.Build.Module.Import;
const Step = std.Build.Step;
const Compile = Step.Compile;
const InstallOptions = Step.InstallArtifact.Options;

const LibLinkageMode = enum {
    static,
    dynamic,
    both,
};

const TestingMode = enum {
    unit,
    lib,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        LibLinkageMode,
        "linkage",
        "Library linkage type: static, dynamic or both",
    ) orelse .dynamic;

    const test_mode = b.option(
        TestingMode,
        "type",
        "Type of tests to build and run: unit, lib (integration)"
    ) orelse .lib;

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
    // engine_mod.addImport("parsing", engine_parsing_mod);
    engine_mod.addImport("types", types_mod);
    engine_mod.addImport("unicode", unicode_mod);

    // Root module for Zig package
    const pkgroot_mod = b.addModule("regrex", .{ 
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

    const c_lib_imports: []const Import = &.{
        .{ .name = "types", .module = types_mod },
        .{ .name = "engine", .module = engine_mod },
    };

    // Initialize the library root module that will be used during build as well
    const libroot_mod = buildLibRootModule(
        b,
        target,
        optimize,
        pkgroot_mod,
        c_lib_imports
    );

    // Build and run test suite
    //
    // Default test mode is unit testing, can be changed with build options
    // e.g. `-zig build test -Dtype=lib`. Acceptable options are `lib` and `unit`
    if (test_mode == .unit) {
        const test_step = b.step("test", "Run inline tests");

        const test_deps = buildTestRunners(b, &.{
            .{ .name = "Unit_root", .root_module = pkgroot_mod },
            .{ .name = "Unit_types", .root_module = types_mod },
            .{ .name = "Unit_engine", .root_module = engine_mod },
            .{ .name = "Unit_unicode", .root_module = unicode_mod },
        });
        for (test_deps)|dep| test_step.dependOn(&b.addRunArtifact(dep).step);
    }

    if (test_mode == .lib) {
        const test_step = b.step(
            "test",
            "Build library and run integration tests"
        );

        const zig_lib_tests_mod = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
        });
        zig_lib_tests_mod.addImport("regrex", pkgroot_mod);

        const c_lib_tests_mod = b.createModule(.{
            .root_source_file = b.path("tests/integration_C.zig"),
            .target = target,
            .optimize = optimize,
        });
        c_lib_tests_mod.addImport("libregrex", libroot_mod);

        const test_deps = buildTestRunners(b, &.{
            .{ .name = "Integration_Zig", .root_module = zig_lib_tests_mod },
            .{ .name = "Integration_C_ABI", .root_module = c_lib_tests_mod },
        });

        for (test_deps)|dep| test_step.dependOn(&b.addRunArtifact(dep).step);
    }

    // Compile and export the library (C-compatible)
    //
    // Default linkage is dynamic, can be changed with build options,
    // e.g. `-Dtype=static`. Option `both` links and compiles both types
    if (linkage == .static or linkage == .both) {
        const static_lib = buildLibrary(b, .static, libroot_mod);
        b.installArtifact(static_lib);
    }

    if (linkage == .dynamic or linkage == .both) {
        const dynamic_lib = buildLibrary(b, .dynamic, libroot_mod);
        b.installArtifact(dynamic_lib);
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

fn buildTestRunners(b: *std.Build, opts: []const std.Build.TestOptions) []*Compile {
    var list: std.ArrayList(*Compile) = .empty;
    errdefer list.deinit(b.allocator);

    for (opts) |option| {
        const test_runner = b.addTest(option);

        list.append(b .allocator, test_runner) catch |err| {
            fatal("ERROR: {any}", .{ err });
        };
    }

    return list.toOwnedSlice(b.allocator) catch |err| fatal("ERROR: {any}", .{ err });
}

/// Compiles the library root module used both for export and for integration testing
///
/// Links `libc` for both static and dynamic linkage
fn buildLibRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pkg_mod: *std.Build.Module,
    imports: []const Import,
) *std.Build.Module {
    const lib_mod = b.addModule("lib", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/regrex.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Zig library package root module
    mod.addImport("regrex", pkg_mod);
    // Namespace module providing Zig types for C ABI implementation
    mod.addImport("lib", lib_mod);

    return mod;
}

/// Compiles the library and includes a C header file
fn buildLibrary(
    b: *std.Build,
    linkage: std.builtin.LinkMode,
    root_mod: *std.Build.Module,
) *Step.Compile {
    const zon = @import("./build.zig.zon");
    const version = std.SemanticVersion.parse(zon.version) catch {
        @panic("Invalid semver format");
    };

    const lib = b.addLibrary(.{
        .name = "regrex",
        .linkage = linkage,
        .root_module = root_mod,
        .version = version,
    });
    lib.installHeader(b.path("include/regrex.h"), "regrex.h");

    return lib;
}
