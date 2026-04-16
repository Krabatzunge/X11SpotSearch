const std = @import("std");
const c = @import("../c.zig").c;
const Xkb = @import("../xkb.zig").Xkb;
const constants = @import("../constants.zig");
const hints = @import("x11_hints.zig");
const utils = @import("../utils.zig");

pub const X11Platform = struct {
    conn: ?*c.xcb_connection_t = null,
    screen: ?*c.xcb_screen_t = null,
    xkb: ?Xkb = null,
    visual: ?*c.xcb_visualtype_t = null,
    surface: ?*c.cairo_surface_t = null,
    cr: ?*c.cairo_t = null,
    win: u32 = 0,
    
    pub fn init() X11Platform {
        return .{};
    }

    pub fn deinit(self: *X11Platform) void {
        if (self.cr) |cr| c.cairo_destroy(cr);
        if (self.surface) |s| c.cairo_surface_destroy(s);
        if (self.xkb) |*xkb| xkb.deinit();
        if (self.conn) |conn| c.xcb_disconnect(conn);
    }

    pub fn determineScreen(self: *X11Platform) !void {
        var screen_num: c_int = 0;
        const conn = c.xcb_connect(null, &screen_num) orelse
            return error.XcbConnectionFailed;

        if (c.xcb_connection_has_error(conn) != 0)
            return error.XcbConnectionHasError;

        const setup = c.xcb_get_setup(conn);
        var iter = c.xcb_setup_roots_iterator(setup);

        var i: c_int = 0;
        while (i < screen_num) : (i += 1) {
            c.xcb_screen_next(&iter);
        }
        const screen = iter.data;

        self.conn = conn;
        self.screen = screen;
    }

    pub fn createWindow(self: *X11Platform) !void {
        const screen = self.screen.?;
        const conn = self.conn.?;
        const x: i16 = @intCast(@divTrunc(@as(i32, screen.*.width_in_pixels) - constants.WIN_WIDTH, 2));
        const y: i16 = @intCast(@divTrunc(@as(i32, screen.*.height_in_pixels) - @as(i32, @intFromFloat(constants.SEARCH_BAR_HEIGHT)), 3));

        self.visual = findVisual(screen) orelse return error.VisualNotFound;
        const colormap = c.xcb_generate_id(conn);
        _ = c.xcb_create_colormap(conn, c.XCB_COLORMAP_ALLOC_NONE, colormap, screen.*.root, self.visual.?.visual_id);

        self.win = c.xcb_generate_id(conn);

        const value_mask = c.XCB_CW_BACK_PIXEL | c.XCB_CW_BORDER_PIXEL | c.XCB_CW_OVERRIDE_REDIRECT | c.XCB_CW_EVENT_MASK | c.XCB_CW_COLORMAP;
        const value_list = [_]u32{
            // XCB_CW_BACK_PIXEL
            0x00000000,
            // XCB_CW_BORDER_PIXEL
            0x00000000,
            // XCB_CW_OVERRIDE_REDIRECT
            1,
            // XCB_CW_EVENT_MASK
            c.XCB_EVENT_MASK_EXPOSURE |
                c.XCB_EVENT_MASK_KEY_PRESS |
                c.XCB_EVENT_MASK_VISIBILITY_CHANGE |
                c.XCB_EVENT_MASK_FOCUS_CHANGE,
            // XCB_CW_COLORMAP
            colormap,
        };

        _ = c.xcb_create_window(conn, 32, self.win, screen.*.root, x, y, constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT, 0, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, self.visual.?.visual_id, value_mask, &value_list);

        hints.setEwmhHints(conn, self.win, screen);
        hints.setMotifHints(conn, self.win);
        setWmClass(conn, self.win);
        hints.setCompositorHints(conn, self.win);

        _ = c.xcb_map_window(conn, self.win);
        _ = c.xcb_set_input_focus(conn, c.XCB_INPUT_FOCUS_POINTER_ROOT, self.win, c.XCB_CURRENT_TIME);
        _ = c.xcb_flush(conn);

        self.xkb = try Xkb.init(conn);

        std.debug.print("Launcher window shown at ({}, {}), size {}x{}\n", .{ x, y, constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT });
    }

    pub fn createSurface(self: *X11Platform) !void {
        const max_height: c_int = @intCast(utils.calcHeight(constants.MAX_RESULTS, true));
        const conn = self.conn.?;
        const surface = c.cairo_xcb_surface_create(conn, self.win, self.visual, constants.WIN_WIDTH, max_height) orelse return error.CairoSurfaceFailed;
        errdefer c.cairo_surface_destroy(surface);
        const cr = c.cairo_create(surface) orelse return error.CairoCreateFailed;
        self.surface = surface;
        self.cr = cr;
    }

    /// Drain the XCB event queue and return the first actionable event.
    /// Returns .close on focus-out, .expose on expose, .key on key-press, .none otherwise.
    pub fn dispatchEvents(self: *X11Platform) @import("../platform.zig").DispatchResult {
        const conn = self.conn orelse return .none;
        while (c.xcb_poll_for_event(conn)) |event| {
            defer std.c.free(event);
            const event_type: u8 = @intCast(event.*.response_type & ~@as(u8, 0x80));
            switch (event_type) {
                c.XCB_EXPOSE => return .expose,
                c.XCB_FOCUS_OUT => return .close,
                c.XCB_KEY_PRESS => {
                    const key_event: *c.xcb_key_press_event_t = @ptrCast(event);
                    if (self.xkb) |*xkb| {
                        xkb.updateState(conn);
                        const r = xkb.processKeyEvent(key_event.detail);
                        return .{ .key = .{ .keysym = r.keysym, .text = r.text } };
                    }
                },
                else => {},
            }
        }
        return .none;
    }

    /// Resize the XCB window and Cairo surface to fit `result_count` results.
    pub fn resize(self: *X11Platform, result_count: usize, has_widget: bool) void {
        const conn = self.conn orelse return;
        const new_height = utils.calcHeight(result_count, has_widget);
        const values = [_]u32{@as(u32, new_height)};
        _ = c.xcb_configure_window(conn, self.win, c.XCB_CONFIG_WINDOW_HEIGHT, &values);
        if (self.surface) |s|
            c.cairo_xcb_surface_set_size(s, constants.WIN_WIDTH, @intCast(new_height));
    }

    fn findVisual(screen: *c.xcb_screen_t) ?*c.xcb_visualtype_t {
        var depth_iter = c.xcb_screen_allowed_depths_iterator(screen);
        while (depth_iter.rem > 0) {
            if (depth_iter.data.*.depth == 32) {
                var visual_iter = c.xcb_depth_visuals_iterator(depth_iter.data);
                while (visual_iter.rem > 0) {
                    if (visual_iter.data.*._class == c.XCB_VISUAL_CLASS_TRUE_COLOR) {
                        return visual_iter.data;
                    }
                    c.xcb_visualtype_next(&visual_iter);
                }
            }
            c.xcb_depth_next(&depth_iter);
        }
        return null;
    }

    fn setWmClass(conn: *c.xcb_connection_t, win: u32) void {
        // WM_CLASS is "instance\0class\0"
        const wm_class = "launcher\x00Launcher\x00";
        _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, c.XCB_ATOM_WM_CLASS, c.XCB_ATOM_STRING, 8, wm_class.len, wm_class.ptr);
    }
};
