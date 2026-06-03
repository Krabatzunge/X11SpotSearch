const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "X11SpotSearch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    const enable_x11 = b.option(bool, "x11", "Enable X11 backend") orelse true;
    const enable_wayland = b.option(bool, "wayland", "Enable Wayland backend") orelse true;

    configureArtifact(exe, b, enable_x11, enable_wayland);

    const options = b.addOptions();
    options.addOption(bool, "enable_x11", enable_x11);
    options.addOption(bool, "enable_wayland", enable_wayland);
    exe.root_module.addOptions("build_options", options);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });
    configureArtifact(exe_tests, b, enable_x11, enable_wayland);
    exe_tests.root_module.addOptions("build_options", options);

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}

fn configureArtifact(
    artifact: *std.Build.Step.Compile,
    b: *std.Build,
    enable_x11: bool,
    enable_wayland: bool,
) void {
    if (enable_x11) {
        artifact.linkSystemLibrary("xcb");
        artifact.linkSystemLibrary("xcb-icccm");
        artifact.linkSystemLibrary("xcb-ewmh");
        artifact.linkSystemLibrary("xcb-xkb");
        artifact.linkSystemLibrary("xkbcommon");
        artifact.linkSystemLibrary("xkbcommon-x11");
    }

    if (enable_wayland) {
        artifact.linkSystemLibrary("wayland-client");

        artifact.addSystemIncludePath(b.path("src/wayland/generated"));
        artifact.addCSourceFile(.{
            .file = b.path("src/wayland/generated/wlr-layer-shell-unstable-v1-client-protocol.c"),
            .flags = &.{"-I", "src/wayland/generated"},
        });
        artifact.addCSourceFile(.{
            .file = b.path("src/wayland/generated/xdg-shell-client-protocol.c"),
            .flags = &.{"-I", "src/wayland/generated"},
        });
    }

    artifact.linkSystemLibrary("xkbcommon");
    artifact.linkSystemLibrary("cairo");
    artifact.linkSystemLibrary("pangocairo");
    artifact.linkSystemLibrary("librsvg-2.0");
    artifact.linkSystemLibrary("curl");
    artifact.linkLibC();
}
