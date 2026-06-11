const std = @import("std");
const Config = @import("config/config.zig").Config;
const Platform = @import("platform.zig").Platform;
const network = @import("network.zig");
const iconMod = @import("icons/icon.zig");
const Renderer = @import("renderer.zig").Renderer;
const constants = @import("constants.zig");
const desktop = @import("desktop.zig");
const WidgetManager = @import("widgets/widget_manager.zig").WidgetManager;
const Result = @import("result.zig").Result;
const fuzzySearch = @import("search.zig");
const c = @import("c.zig").c;
const timer = @import("timer.zig");
const geo_loc_extract = @import("network/parsers/geo_location.zig");
const launcher = @import("launcher.zig");
const IconStruct = @import("icons/icon_struct.zig").Icon;
const EmbeddedIcons = @import("assets.zig").Icons;
const dtypes = @import("draw_utils/types.zig");
const cattpuccin = @import("themes/cattpuccin.zig");
const result_item = @import("widgets/result_item.zig");
const RenderContext = @import("draw_utils/context.zig").RenderContext;

const SearchData = struct {
    search_buf: [256]u8 = undefined,
    search_len: usize = 0,

    results_buf: [constants.MAX_RESULTS]Result = undefined,
    scored_buf: [constants.MAX_RESULTS]fuzzySearch.ScoredEntry = undefined,
    results_count: usize = 0,
    selected: usize = 0,
    search_tag: fuzzySearch.SearchTag = .Unspecified,
    cleaned_search_query: []const u8 = "",
    web_search_desc_buf: [256]u8 = undefined,
};

const RenderData = struct {
    cursor_visible: bool = true,
};

pub const Runtime = struct {
    config: *Config,
    platform: *Platform,
    gpa: std.mem.Allocator,

    net: *network.AsyncCurl,
    locReq: ?*network.CurlRequest,

    iconEventFd: i32,
    icons: iconMod.IconModule,

    renderer: Renderer,

    scanner: desktop.DesktopScanner,
    widgetManager: WidgetManager,

    searchData: SearchData,
    renderData: RenderData,

    pub fn init(self: *Runtime, gpa: std.mem.Allocator, config: *Config, platform: *Platform) !void {
        self.gpa = gpa;
        self.config = config;
        self.platform = platform;

        switch (platform.*) {
            .x11 => |*p| {
                try p.createWindow();
                try p.createSurface();
            },
            .wayland => {}, 
        }

        self.net = try network.AsyncCurl.init(self.gpa);
        self.locReq = null;

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
                    self.locReq = try self.net.fetch(url);
                }
            }
        }

        self.iconEventFd = try std.posix.eventfd(0, std.os.linux.EFD.CLOEXEC);
        self.icons = try iconMod.IconModule.init(std.heap.page_allocator);
        try self.icons.startLoader(self.gpa, self.iconEventFd);

        self.renderer = try Renderer.init(constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT, &self.icons);

        self.scanner = desktop.DesktopScanner.init(std.heap.page_allocator);
        try self.scanner.scan();
        std.debug.print("Loaded {} desktop entries\n", .{self.scanner.entries.items.len});

        self.widgetManager = WidgetManager.init(std.heap.page_allocator);
        try self.widgetManager.setup(self.net, config, &self.config.loc);

        self.searchData = .{};
        self.renderData = .{};
    }

    pub fn deinit(self: *Runtime) void {
        if (self.locReq) |req| self.net.release(req);
        self.net.deinit();
        std.posix.close(self.iconEventFd);
        self.icons.deinit();
        self.renderer.deinit();
        self.scanner.deinit();
        self.widgetManager.deinit();
    }

    pub fn run(self: *Runtime) !void {
        // Initial draw
        if (self.platform.beginFrame()) |cr| {
            self.renderer.beginFrame();
            self.draw();
            self.renderer.endFrame(cr);
            self.platform.commitFrame();
        }

        const window_fd = self.platform.getFd();
        const ctimer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC);
        defer std.posix.close(ctimer_fd);
        const ftimer_fd = c.timerfd_create(c.CLOCK_MONOTONIC, c.TFD_CLOEXEC); // Frame timer (60fps)

        timer.armTimer(ctimer_fd, constants.CURSOR_BLINK_MS, constants.CURSOR_BLINK_MS);
        timer.armTimer(ftimer_fd, constants.FRAME_MS, constants.FRAME_MS);

        var fds = [_]c.struct_pollfd{
            .{ .fd = window_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = ctimer_fd, .events = c.POLLIN, .revents = 0 },
            .{ .fd = self.iconEventFd, .events = c.POLLIN, .revents = 0},
        };

        var needs_redraw = false;

        while (!self.platform.shouldClose()) {
            self.platform.prePoll();
            _ = c.poll(&fds, 3, -1);

            if (self.locReq) |req| {
                const loc_res = self.net.try_value(req) catch |err| blk: {
                    std.debug.print("Geolocation request failed: {}\n", .{err});
                    self.net.release(req);
                    self.locReq = null;
                    break :blk null;
                };
                if (loc_res) |res| {
                    const p_loc: ?geo_loc_extract.GeoResult = geo_loc_extract.extract_geo_location(self.gpa, res) catch |err| blk: {
                        std.debug.print("Failed to extract geolocation: {}\n", .{err});
                        break :blk null;
                    };
                    if (p_loc) |loc| {
                        self.config.loc.lat = loc.latitude;
                        self.config.loc.lon = loc.longitude;
                        std.debug.print("Resolved location: lat {d} lon {d}\n", .{ loc.latitude, loc.longitude });
                    }
                    self.net.release(req);
                    self.locReq = null;
                }
            }

            if (fds[2].revents & c.POLLIN != 0) {
                var buf: u64 = 0;
                _ = std.posix.read(self.iconEventFd, std.mem.asBytes(&buf)) catch {};
                needs_redraw = true;
            }

            if (fds[1].revents & c.POLLIN != 0) {
                var expirations: u64 = 0;
                _ = std.posix.read(ctimer_fd, std.mem.asBytes(&expirations)) catch continue;
                self.renderData.cursor_visible = !self.renderData.cursor_visible;
                needs_redraw = true;
            }

            if (fds[0].revents & c.POLLIN != 0) {
                switch (self.platform.dispatchEvents()) {
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
                                std.debug.print("Enter pressed: \"{s}\"\n", .{self.searchData.search_buf[0..self.searchData.search_len]});
                                if (self.searchData.results_count > 0) {
                                    const scored = fuzzySearch.search(self.scanner.entries.items, self.config.search.engines, self.searchData.search_buf[0..self.searchData.search_len], &self.searchData.scored_buf);
                                    if (self.searchData.selected < scored.entries.len) {
                                        launcher.launchDesktopEntry(scored.entries[self.searchData.selected].entry) catch |err| {
                                            std.debug.print("Launch failed: {}\n", .{err});
                                        };
                                        return;
                                    }
                                    const attach_select = self.searchData.selected - scored.entries.len;
                                    switch (attach_select) {
                                        0 => {
                                            std.debug.print("Opening with engine {s}\n", .{self.config.search.search_engine});
                                            launcher.launchWebSearch(self.searchData.cleaned_search_query, self.config.search.search_engine) catch |err| {
                                                std.debug.print("Opening browser failed {}\n", .{err});
                                            };    
                                            return;
                                        },
                                        else => {},
                                    }
                                }
                            },
                            c.XKB_KEY_BackSpace => {
                                if (self.searchData.search_len > 0) {
                                    self.searchData.search_len -= 1;
                                    while (self.searchData.search_len > 0 and (self.searchData.search_buf[self.searchData.search_len] & 0xC0) == 0x80)
                                        self.searchData.search_len -= 1;
                                    search_changed = true;
                                }
                            },
                            c.XKB_KEY_Up => {
                                if (self.searchData.selected > 0) self.searchData.selected -= 1;
                            },
                            c.XKB_KEY_Down => {
                                if (self.searchData.results_count > 0 and self.searchData.selected < self.searchData.results_count - 1) self.searchData.selected += 1;
                            },
                            else => {
                                if (key.text) |txt| {
                                    if (self.searchData.search_len + txt.len < self.searchData.search_buf.len) {
                                        @memcpy(self.searchData.search_buf[self.searchData.search_len .. self.searchData.search_len + txt.len], txt);
                                        self.searchData.search_len += txt.len;
                                        search_changed = true;
                                    }
                                }
                            },
                        }

                        if (search_changed) {
                            self.renderData.cursor_visible = true;
                            timer.armTimer(ctimer_fd, constants.CURSOR_BLINK_MS, constants.CURSOR_BLINK_MS);
                            self.searchData.results_count = 0;
                            self.searchData.selected = 0;
                            if (self.searchData.search_len > 0) {
                                self.widgetManager.determineWidget(self.searchData.search_buf[0..self.searchData.search_len]);
                                const search_res = fuzzySearch.search(self.scanner.entries.items, self.config.search.engines, self.searchData.search_buf[0..self.searchData.search_len], &self.searchData.scored_buf);
                                self.searchData.search_tag = search_res.tag;
                                self.searchData.cleaned_search_query = search_res.query;
                                for (search_res.entries, 0..) |s, idx| {
                                    self.searchData.results_buf[idx] = .{
                                        .name = s.entry.name,
                                        .description = if (s.entry.comment.len > 0) s.entry.comment else s.entry.exec,
                                        .icon = s.entry.icon,
                                        .selected = false,
                                    };
                                }
                                self.searchData.results_count = search_res.entries.len;
                                if (search_res.entries.len < constants.MAX_RESULTS and fuzzySearch.startsWithTag(self.searchData.cleaned_search_query) == false) {
                                    self.searchData.results_buf[search_res.entries.len] = .{
                                        .name = "Search the web",
                                        .description = std.fmt.bufPrint(&self.searchData.web_search_desc_buf, "Search the web for: {s}", .{self.searchData.cleaned_search_query}) catch "Search the web", //TODO: add formatting by either using buffer or allocator. Rather need allocator because of lifetime
                                        .icon = IconStruct.initEmbedded(EmbeddedIcons.Browser), // TODO: chage web search icon color to Mauve
                                        .selected = false,
                                    };
                                    self.searchData.results_count += 1;
                                }
                            } else {
                                self.searchData.cleaned_search_query = "";
                                self.searchData.search_tag = .Unspecified;
                            }
                        }

                        for (self.searchData.results_buf[0..self.searchData.results_count], 0..) |*r, j| r.selected = (j == self.searchData.selected);

                        const has_widget = self.widgetManager.active_widget != null;
                        self.platform.resize(self.searchData.results_count, has_widget);
                        self.renderer.height = @import("utils.zig").calcHeight(self.searchData.results_count, has_widget);
                        needs_redraw = true;
                    },
                }
            }

            if (needs_redraw) {
                if (self.platform.beginFrame()) |cr| {
                    self.renderer.beginFrame();
                    //self.renderer.draw(cr, self.searchData.cleaned_search_query, self.searchData.search_tag, self.searchData.results_buf[0..self.searchData.results_count], self.renderData.cursor_visible, self.widgetManager.active_widget);
                    self.draw();
                    self.renderer.endFrame(cr);
                    self.platform.commitFrame();
                }
                needs_redraw = false;
            }
        }
    }

    fn draw(self: *Runtime) void {
        const width = self.renderer.width;
        const height = self.renderer.height;
        const renderTagChip = self.searchData.search_tag != fuzzySearch.SearchTag.Unspecified;

        self.renderer.drawRectangle(0.0, 0.0, @as(f64, @floatFromInt(width)), @as(f64, @floatFromInt(height)), cattpuccin.base, dtypes.Rounding.all(16.0), dtypes.Border.all(1.5, cattpuccin.overlay1, dtypes.Rounding.all(16.0), dtypes.BorderType.Inner));

        const margin: f64 = 6.0;
        const bar_x = margin;
        const bar_y = margin;
        const bar_h = constants.SEARCH_BAR_HEIGHT - margin * 2.0;
        const search_chip_margin: f64 = 6.0;
        const padding: f64 = 16.0;

        var search_chip_width: f64 = 0;

        // SeachTag Chip
        if (renderTagChip) {
            const chip_x = bar_x + search_chip_margin;
            const chip_y = bar_y + search_chip_margin;

            const c_padding: f64 = 8.0;
            const display_text = @tagName(self.searchData.search_tag);
            const txt_size = self.renderer.measureText(display_text, .chip);

            search_chip_width = c_padding * 2 + @as(f64, @floatFromInt(txt_size.w));
            const c_height = bar_h - search_chip_margin * 2;

            const text_x = chip_x + c_padding;
            const text_y = chip_y + (c_height - @as(f64, @floatFromInt(txt_size.h))) / 2.0;

            self.renderer.drawRectangle(chip_x, chip_y, search_chip_width, c_height, cattpuccin.surface0, dtypes.Rounding.all(12.0), dtypes.Border.all(1.5, cattpuccin.overlay0, dtypes.Rounding.all(12.0), dtypes.BorderType.Inner));
            _ = self.renderer.drawText(display_text, .chip, cattpuccin.text, text_x, text_y);
        }

        // Text input field
        {
            const text_x = bar_x + padding + search_chip_width;
            const display_text = if (self.searchData.search_len == 0) "Search..." else self.searchData.search_buf[0..self.searchData.search_len];
            const display_color = if (self.searchData.search_len == 0) cattpuccin.subtext1 else cattpuccin.text;

            const size = self.renderer.measureText(display_text, .input);
            const text_y = bar_y + (bar_h - @as(f64, @floatFromInt(size.h))) / 2.0;
            const text_w = self.renderer.drawText(display_text, .input, display_color, text_x, text_y).w;

            if (self.renderData.cursor_visible) {
                const cursor_w = if (self.searchData.search_len == 0) -2 else text_w;
                const cursor_x = text_x + @as(f64, @floatFromInt(cursor_w)) + 2.0;
                const cursor_y = bar_y + 10.0;
                const cursor_h = bar_h - 20.0;
                self.renderer.drawRectangle(cursor_x, cursor_y, 2.0, cursor_h, cattpuccin.text, dtypes.Rounding.all(2.0), dtypes.Border.None);
            }
        }

        // Result list
        if (self.searchData.results_count > 0) {
            // Seperator line
            self.renderer.drawRectangle(0.0, constants.SEARCH_BAR_HEIGHT - 1.0, @as(f64, constants.WIN_WIDTH), 1.5, cattpuccin.overlay1, dtypes.Rounding.all(0.0), dtypes.Border.None);

            for (self.searchData.results_buf[0..self.searchData.results_count], 0..) |result, i| {
                const iy: f64 = @floatFromInt(i);
                const item_y = constants.SEARCH_BAR_HEIGHT + constants.SEPERATOR_PADDING + iy * constants.RESULT_ITEM_HEIGHT;
                const res_icon = self.renderer.iconMod.loadIcon(result.icon, constants.ICON_SIZE, cattpuccin.text);
                result_item.draw(&result, &self.renderer, item_y, res_icon);
            }
        }

        // Widget
        if (self.widgetManager.active_widget) |w| {
            const results_f: f64 = @floatFromInt(self.searchData.results_count);
            const widget_sep_y = constants.SEARCH_BAR_HEIGHT + results_f * constants.RESULT_ITEM_HEIGHT + constants.SEPERATOR_PADDING * 2;

            self.renderer.drawRectangle(0.0, widget_sep_y, @as(f64, constants.WIN_WIDTH), 1.5, cattpuccin.overlay1, dtypes.Rounding.all(0.0), dtypes.Border.None);

            w.draw(w.ctx, &self.renderer, widget_sep_y + 1.0, self.searchData.search_buf[0..self.searchData.search_len]);
        }
    }
};
