const std = @import("std");
const c = @import("c.zig").c;
const Renderer = @import("renderer.zig").Renderer;
const constants = @import("constants.zig");
const Result = @import("result.zig").Result;
const desktop = @import("desktop.zig");
const fuzzy_match = @import("search.zig");
const launcher = @import("launcher.zig");
const mode_config = @import("mode.zig");
const deamon = @import("deamon.zig");
const icon_mod = @import("icons/icon.zig");
const WidgetManager = @import("widgets/widget_manager.zig").WidgetManager;
const Config = @import("config/config.zig").Config;
const ConfigParser = @import("config/config_parser.zig").ConfigParser;
const network = @import("network.zig");
const geo_loc_extract = @import("network/parsers/geo_location.zig");
const build_options = @import("build_options");
const X11Platform = @import("x11/x11_platform.zig").X11Platform;
const WaylandPlatform = @import("wayland/wl_platform.zig").WaylandPlatform;
const platform_mod = @import("platform.zig");
const Platform = platform_mod.Platform;
const EmbeddedIcons = @import("assets.zig").Icons;
const IconStruct = @import("icons/icon_struct.zig").Icon;
const Runtime = @import("runtime.zig").Runtime;

pub fn main() !void {
    const run_config = mode_config.parse();

    if (run_config.session_type == .wayland and !build_options.enable_wayland) {
        std.debug.print("You are running a non-wayland binary in a wayland session.\n", .{});
        std.debug.print("Please switch to a wayland binary or a binary supporting it.\n", .{});
        return;
    }
    if (run_config.session_type == .x11 and !build_options.enable_x11) {
        std.debug.print("You are running a non-x11 binary in an x11 session.\n", .{});
        std.debug.print("Please switch to an x11 binary or a binary supporting it.\n", .{});
        return;
    }

    var config_parser = ConfigParser.init(std.heap.page_allocator);
    defer config_parser.deinit();
    const config = config_parser.parseConfig();

    var platform: Platform = switch (run_config.session_type) {
        .x11 => blk: {
            var p = X11Platform.init();
            p.determineScreen() catch {
                std.debug.print("X11 screen determination failed\n", .{});
                return;
            };
            break :blk .{ .x11 = p };
        },
        .wayland => .{ .wayland = WaylandPlatform.init() catch |err| {
            std.debug.print("Wayland init failed: {}\n", .{err});
            return;
        } },
        .tty => {
            std.debug.print("TTY session detected — no display server available.\n", .{});
            return;
        },
    };
    defer platform.deinit();

    switch (platform) {
        .wayland => |*p| p.setupSurface() catch |err| {
            std.debug.print("Wayland surface setup failed: {}\n", .{err});
            return;
        },
        else => {},
    }

    switch (run_config.mode) {
        .oneshot => try runLauncher(config, &platform),
        .daemon => try runAsDaemon(config, &platform),
    }
}

fn runAsDaemon(config: Config, platform: *Platform) !void {
    switch (platform.*) {
        .x11 => |*p| {
            const conn = p.conn.?;
            const screen = p.screen.?;
            try deamon.runDeamon(conn, screen.*.root, config.hotkey_mod, config.hotkey_keysym, spawnOneshot);
        },
        .wayland => {
            std.debug.print("Daemon mode is not supported on Wayland.\n", .{});
            std.debug.print("Please set the hotkey with oneshot mode in your compositor config.\n", .{});
        },
    }
}

fn spawnOneshot() void {
    const argv = [_:null]?[*:0]const u8{
        "/proc/self/exe", //Linux points to own binary
        null,
    };

    const pid = std.posix.fork() catch return;
    if (pid == 0) {
        switch (std.posix.execvpeZ("/proc/self/exe", &argv, @ptrCast(std.c.environ))) {
            else => std.posix.exit(1),
        }
    }
    _ = std.posix.waitpid(pid, 0);
}

fn runLauncher(config: Config, platform: *Platform) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const g_alloc = gpa.allocator();

    var runtime: *Runtime = try g_alloc.create(Runtime);
    defer g_alloc.destroy(runtime);
    try runtime.init(g_alloc, @constCast(&config), platform);
    defer runtime.deinit();

    try runtime.run();
}

fn armTimer(timer_fd: c_int, initial_ms: u32, repeat_ms: u32) void {
    const ms_to_ns = 1_000_000;
    const its = c.struct_itimerspec{
        .it_value = .{
            .tv_sec = 0,
            .tv_nsec = @as(c_long, initial_ms) * ms_to_ns,
        },
        .it_interval = .{
            .tv_sec = 0,
            .tv_nsec = @as(c_long, repeat_ms) * ms_to_ns,
        },
    };
    _ = c.timerfd_settime(timer_fd, 0, &its, null);
}
