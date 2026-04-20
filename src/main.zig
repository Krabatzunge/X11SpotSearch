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
    var active_loc = config.loc;

    switch (platform.*) {
        .x11 => |*p| {
            try p.createWindow();
            try p.createSurface();
        },
        .wayland => {}, 
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const g_alloc = gpa.allocator();
    var net = try network.AsyncCurl.init(g_alloc);
    defer net.deinit();

    var loc_req: ?*network.CurlRequest = null;
    defer if (loc_req) |req| net.release(req);

    if (config.loc.lat == null and config.loc.lon == null) {
        if (config.loc.city) |city| {
            var loc_req_buf: [128]u8 = undefined;
            const loc_req_url: ?[]const u8 = std.fmt.bufPrint(
                &loc_req_buf,
                "https://geocoding-api.open-meteo.com/v1/search?name={s}&count=1&language={s}&format=json",
                .{ city, config.loc.lang },
            ) catch null;
            if (loc_req_url) |url| {
                std.debug.print("Fetching geolocation based on city: {s}\n", .{city});
                loc_req = try net.fetch(url);
            }
        }
    }

    var renderer = try Renderer.init(constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT);
    defer renderer.deinit();

    var scanner = desktop.DesktopScanner.init(std.heap.page_allocator);
    defer scanner.deinit();
    try scanner.scan();
    std.debug.print("Loaded {} desktop entries\n", .{scanner.entries.items.len});

    const icon_event_fd = try std.posix.eventfd(0, std.os.linux.EFD.CLOEXEC);
    defer std.posix.close(icon_event_fd);
    var icons = try icon_mod.IconModule.init(std.heap.page_allocator);
    defer icons.deinit();
    try icons.startLoader(g_alloc, icon_event_fd);

    var widget_manager = WidgetManager.init(std.heap.page_allocator);
    try widget_manager.setup(net, config, &active_loc);
    defer widget_manager.deinit();

    var search_buf: [256]u8 = undefined;
    var search_len: usize = 0;

    var results_buf: [constants.MAX_RESULTS]Result = undefined;
    var scored_buf: [constants.MAX_RESULTS]fuzzy_match.ScoredEntry = undefined;
    var results_count: usize = 0;
    var selected: usize = 0;
    var search_tag: fuzzy_match.SearchTag = .Unspecified;
    var cleaned_search_query: []const u8 = "";

    // Initial draw
    if (platform.beginFrame()) |cr| {
        renderer.draw(cr, cleaned_search_query, search_tag, results_buf[0..0], &icons, true, null);
        platform.commitFrame();
    }

    const window_fd = platform.getFd();
    const ctimer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC);
    defer std.posix.close(ctimer_fd);
    const ftimer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC); // Frame timer (60fps)

    armTimer(ctimer_fd, constants.CURSOR_BLINK_MS, constants.CURSOR_BLINK_MS);
    armTimer(ftimer_fd, constants.FRAME_MS, constants.FRAME_MS);

    var fds = [_]c.struct_pollfd{
        .{ .fd = window_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = ctimer_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = icon_event_fd, .events = c.POLLIN, .revents = 0},
    };

    var cursor_visible = true;
    var needs_redraw = false;

    while (!platform.shouldClose()) {
        platform.prePoll();
        _ = c.poll(&fds, 3, -1);

        if (loc_req) |req| {
            const loc_res = net.try_value(req) catch |err| blk: {
                std.debug.print("Geolocation request failed: {}\n", .{err});
                net.release(req);
                loc_req = null;
                break :blk null;
            };
            if (loc_res) |res| {
                const p_loc: ?geo_loc_extract.GeoResult = geo_loc_extract.extract_geo_location(g_alloc, res) catch |err| blk: {
                    std.debug.print("Failed to extract geolocation: {}\n", .{err});
                    break :blk null;
                };
                if (p_loc) |loc| {
                    active_loc.lat = loc.latitude;
                    active_loc.lon = loc.longitude;
                    std.debug.print("Resolved location: lat {d} lon {d}\n", .{ loc.latitude, loc.longitude });
                }
                net.release(req);
                loc_req = null;
            }
        }

        if (fds[2].revents & c.POLLIN != 0) {
            var buf: u64 = 0;
            _ = std.posix.read(icon_event_fd, std.mem.asBytes(&buf)) catch {};
            needs_redraw = true;
        }

        if (fds[1].revents & c.POLLIN != 0) {
            var expirations: u64 = 0;
            _ = std.posix.read(ctimer_fd, std.mem.asBytes(&expirations)) catch continue;
            cursor_visible = !cursor_visible;
            needs_redraw = true;
        }

        if (fds[0].revents & c.POLLIN != 0) {
            switch (platform.dispatchEvents()) {
                .close => return,
                .expose => needs_redraw = true,
                .none => {},
                .key => |key| {
                    var search_changed = false;

                    switch (key.keysym) {
                        c.XKB_KEY_Escape => {
                            std.debug.print("Escape pressed, exiting.\n", .{});
                            return;
                        },
                        c.XKB_KEY_Return, c.XKB_KEY_KP_Enter => {
                            std.debug.print("Enter pressed: \"{s}\"\n", .{search_buf[0..search_len]});
                            if (results_count > 0) {
                                const scored = fuzzy_match.search(scanner.entries.items, search_buf[0..search_len], &scored_buf);
                                if (selected < scored.entries.len) {
                                    launcher.launch(scored.entries[selected].entry) catch |err| {
                                        std.debug.print("Launch failed: {}\n", .{err});
                                    };
                                    return;
                                }
                            }
                        },
                        c.XKB_KEY_BackSpace => {
                            if (search_len > 0) {
                                search_len -= 1;
                                while (search_len > 0 and (search_buf[search_len] & 0xC0) == 0x80)
                                    search_len -= 1;
                                search_changed = true;
                                std.debug.print("Search: \"{s}\"\n", .{search_buf[0..search_len]});
                            }
                        },
                        c.XKB_KEY_Up => {
                            if (selected > 0) selected -= 1;
                            std.debug.print("Going up, selected: {}\n", .{selected});
                        },
                        c.XKB_KEY_Down => {
                            if (results_count > 0 and selected < results_count - 1) selected += 1;
                            std.debug.print("Going down, selected: {}\n", .{selected});
                        },
                        else => {
                            if (key.text) |txt| {
                                if (search_len + txt.len < search_buf.len) {
                                    @memcpy(search_buf[search_len .. search_len + txt.len], txt);
                                    search_len += txt.len;
                                    search_changed = true;
                                    std.debug.print("Search: \"{s}\"\n", .{search_buf[0..search_len]});
                                }
                            }
                        },
                    }

                    if (search_changed) {
                        cursor_visible = true;
                        armTimer(ctimer_fd, constants.CURSOR_BLINK_MS, constants.CURSOR_BLINK_MS);
                        results_count = 0;
                        selected = 0;
                        if (search_len > 0) {
                            widget_manager.determineWidget(search_buf[0..search_len]);
                            const search_res = fuzzy_match.search(scanner.entries.items, search_buf[0..search_len], &scored_buf);
                            search_tag = search_res.tag;
                            cleaned_search_query = search_res.query;
                            for (search_res.entries, 0..) |s, idx| {
                                results_buf[idx] = .{
                                    .name = s.entry.name,
                                    .description = if (s.entry.comment.len > 0) s.entry.comment else s.entry.exec,
                                    .icon = s.entry.icon,
                                    .selected = false,
                                };
                            }
                            results_count = search_res.entries.len;
                        } else {
                            cleaned_search_query = "";
                            search_tag = .Unspecified;
                        }
                    }

                    for (results_buf[0..results_count], 0..) |*r, j| r.selected = (j == selected);

                    const has_widget = widget_manager.active_widget != null;
                    platform.resize(results_count, has_widget);
                    renderer.height = @import("utils.zig").calcHeight(results_count, has_widget);
                    needs_redraw = true;
                },
            }
        }

        if (needs_redraw) {
            if (platform.beginFrame()) |cr| {
                renderer.draw(cr, cleaned_search_query, search_tag, results_buf[0..results_count], &icons, cursor_visible, widget_manager.active_widget);
                platform.commitFrame();
            }
            needs_redraw = false;
        }
    }
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
