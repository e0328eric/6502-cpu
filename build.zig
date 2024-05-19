const std = @import("std");
const builtin = @import("builtin");

const min_zig_version_str = "0.13.0-dev.211+6a65561e3";

const Build = blk: {
    const current_zig_version_str = builtin.zig_version_string;

    const current_zig_version = builtin.zig_version;
    const min_zig_version = std.SemanticVersion.parse(min_zig_version_str) catch unreachable;

    if (current_zig_version.order(min_zig_version) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Required at least v{s}, but current zig version is v{s}.\n",
            .{ min_zig_version_str, current_zig_version_str },
        ));
    }
    break :blk std.Build;
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = try std.SemanticVersion.parse("0.1.0");

    const lib = b.addModule("pixeka", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "pixeka",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .version = version,
    });
    linkRaylib(b, exe, target, optimize);
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("pixeka", lib);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

// NOTE: Stolen from https://github.com/Not-Nik/raylib-zig/blob/devel/build.zig
fn linkRaylib(
    b: *Build,
    exe: *Build.Step.Compile,
    target: Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) void {
    const raylib = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    const art = raylib.artifact("raylib");

    const target_os = exe.rootModuleTarget();
    switch (target_os.os.tag) {
        .windows => {
            exe.linkSystemLibrary("winmm");
            exe.linkSystemLibrary("gdi32");
            exe.linkSystemLibrary("opengl32");
        },
        .macos => {
            exe.linkFramework("OpenGL");
            exe.linkFramework("Cocoa");
            exe.linkFramework("IOKit");
            exe.linkFramework("CoreAudio");
            exe.linkFramework("CoreVideo");
        },
        .freebsd, .openbsd, .netbsd, .dragonfly => {
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
            exe.linkSystemLibrary("Xrandr");
            exe.linkSystemLibrary("Xinerama");
            exe.linkSystemLibrary("Xi");
            exe.linkSystemLibrary("Xxf86vm");
            exe.linkSystemLibrary("Xcursor");
        },
        .emscripten, .wasi => {
            // When using emscripten, the libries don't need to be linked
            // because emscripten is going to do that later.
        },
        else => { // Linux and possibly others.
            exe.linkSystemLibrary("GL");
            exe.linkSystemLibrary("rt");
            exe.linkSystemLibrary("dl");
            exe.linkSystemLibrary("m");
            exe.linkSystemLibrary("X11");
        },
    }

    exe.linkLibrary(art);
}
