const std = @import("std");
const c = @import("c.zig").c;
const utils = @import("utils.zig");
const constants = @import("constants.zig");
const Result = @import("result.zig").Result;
const icon_mod = @import("icon.zig");

pub const Renderer = struct {
    surface: *c.cairo_surface_t,
    cr: *c.cairo_t,
    width: u16,
    height: u16,

    const bg_r: f64 = 0x1e.0 / 255.0;
    const bg_g: f64 = 0x1e.0 / 255.0;
    const bg_b: f64 = 0x2e.0 / 255.0;

    const fg_r: f64 = 0xcd.0 / 255.0;
    const fg_g: f64 = 0xd6.0 / 255.0;
    const fg_b: f64 = 0xf4.0 / 255.0;

    const placeholder_r: f64 = 0x6c.0 / 255.0;
    const placeholder_g: f64 = 0x70.0 / 255.0;
    const placeholder_b: f64 = 0x86.0 / 255.0;

    const padding: f64 = 16.0;
    const font_desc_str = "Inter, DejaVu Sans, Liberation Sans, Noto Sans, Arial, Helvetica, Sans 20";
    const font_desc_small_str = "Inter, DejaVu Sans, Noto Sans, Sans 13";

    pub const icon_padding: f64 = 8.0;
    pub const text_left: f64 = padding + @as(f64, @floatFromInt(constants.ICON_SIZE)) + icon_padding;

    pub fn init(conn: *c.xcb_connection_t, screen: *c.xcb_screen_t, win: u32, visual: *c.xcb_visualtype_t, width: u16, height: u16) !Renderer {
        const surface = c.cairo_xcb_surface_create(conn, win, visual, width, @intCast(utils.calcHeight(constants.MAX_RESULTS))) orelse return error.CairoSurfaceFailed;
        errdefer c.cairo_surface_destroy(surface);

        const cr = c.cairo_create(surface) orelse return error.CairoCreateFailed;

        const font_opts = c.cairo_font_options_create();
        defer c.cairo_font_options_destroy(font_opts);
        c.cairo_font_options_set_antialias(font_opts, c.CAIRO_ANTIALIAS_SUBPIXEL);
        c.cairo_set_font_options(cr, font_opts);

        _ = screen;

        return .{ .surface = surface, .cr = cr, .width = width, .height = height };
    }

    pub fn deinit(self: *Renderer) void {
        c.cairo_destroy(self.cr);
        c.cairo_surface_destroy(self.surface);
    }

    pub fn draw(self: *Renderer, search_text: []const u8, results: []const Result, icons: *icon_mod.IconCache, cursor_visible: bool) void {
        const cr = self.cr;
        const width = self.width;

        c.cairo_set_source_rgb(cr, bg_r, bg_g, bg_b);
        c.cairo_paint(cr);

        const margin: f64 = 6.0;
        const bar_x = margin;
        const bar_y = margin;
        const bar_w = @as(f64, @floatFromInt(width)) - margin * 2.0;
        const bar_h = constants.SEARCH_BAR_HEIGHT - margin * 2.0;
        const radius: f64 = 10.0;

        roundedRect(cr, bar_x, bar_y, bar_w, bar_h, radius);
        c.cairo_set_source_rgb(cr, 0x31.0 / 255.0, 0x31.0 / 255.0, 0x44.0 / 255.0);
        c.cairo_fill(cr);

        // Text input field
        {
            const layout = c.pango_cairo_create_layout(cr) orelse return;
            defer c.g_object_unref(layout);

            const font_desc = c.pango_font_description_from_string(font_desc_str);
            defer c.pango_font_description_free(font_desc);
            c.pango_layout_set_font_description(layout, font_desc);

            if (search_text.len == 0) {
                c.cairo_set_source_rgb(cr, placeholder_r, placeholder_g, placeholder_b);
                c.pango_layout_set_text(layout, "Search...", -1);
            } else {
                c.cairo_set_source_rgb(cr, fg_r, fg_g, fg_b);
                c.pango_layout_set_text(layout, search_text.ptr, @intCast(search_text.len));
            }

            var text_w: c_int = 0;
            var text_h: c_int = 0;
            c.pango_layout_get_pixel_size(layout, &text_w, &text_h);

            const text_x = bar_x + padding;
            const text_y = bar_y + (bar_h - @as(f64, @floatFromInt(text_h))) / 2.0;

            c.cairo_move_to(cr, text_x, text_y);
            c.pango_cairo_show_layout(cr, layout);

            if (search_text.len == 0)
                text_w = -2;

            if (cursor_visible) {
                c.cairo_set_source_rgb(cr, fg_r, fg_g, fg_b);
                const cursor_x = text_x + @as(f64, @floatFromInt(text_w)) + 2.0;
                const cursor_y = bar_y + 10.0;
                const cursor_h = bar_h - 20.0;
                c.cairo_rectangle(cr, cursor_x, cursor_y, 2.0, cursor_h);
                c.cairo_fill(cr);
            }
        }

        // Result list
        if (results.len > 0) {
            c.cairo_set_source_rgb(cr, 0x45.0 / 255.0, 0x47.0 / 255.0, 0x5a.0 / 255.0);
            c.cairo_rectangle(cr, 12.0, constants.SEARCH_BAR_HEIGHT - 1.0, @as(f64, constants.WIN_WIDTH) - 24.0, 1.0);
            c.cairo_fill(cr);

            for (results, 0..) |result, i| {
                const iy: f64 = @floatFromInt(i);
                const item_y = constants.SEARCH_BAR_HEIGHT + iy * constants.RESULT_ITEM_HEIGHT;

                if (result.selected) {
                    roundedRect(cr, 6.0, item_y + 2.0, @as(f64, constants.WIN_WIDTH) - 12.0, constants.RESULT_ITEM_HEIGHT - 4.0, 8.0);
                    c.cairo_set_source_rgb(cr, 0x45.0 / 255.0, 0x47.0 / 255.0, 0x5a.0 / 255.0);
                    c.cairo_fill(cr);
                }

                if (icons.get(result.icon_name)) |icon_surface| {
                    const icon_x: f64 = 14.0;
                    const icon_y: f64 = item_y + (constants.RESULT_ITEM_HEIGHT - @as(f64, @floatFromInt(constants.ICON_SIZE))) / 2.0;

                    c.cairo_set_source_surface(cr, icon_surface, icon_x, icon_y);
                    c.cairo_paint(cr);
                }

                // Result name
                {
                    const layout = c.pango_cairo_create_layout(cr) orelse continue;
                    defer c.g_object_unref(layout);

                    const fd = c.pango_font_description_from_string(font_desc_str);
                    defer c.pango_font_description_free(fd);
                    c.pango_layout_set_font_description(layout, fd);
                    c.pango_layout_set_text(layout, result.name.ptr, @intCast(result.name.len));

                    if (result.selected) {
                        c.cairo_set_source_rgb(cr, fg_r, fg_g, fg_b);
                    } else {
                        c.cairo_set_source_rgb(cr, 0xba.0 / 255.0, 0xc2.0 / 255.0, 0xde.0 / 255.0);
                    }

                    c.cairo_move_to(cr, text_left, item_y + 8.0);
                    c.pango_cairo_show_layout(cr, layout);
                }
                // Result description
                {
                    const layout = c.pango_cairo_create_layout(cr) orelse continue;
                    defer c.g_object_unref(layout);

                    const fd = c.pango_font_description_from_string(font_desc_small_str);
                    defer c.pango_font_description_free(fd);
                    c.pango_layout_set_font_description(layout, fd);
                    c.pango_layout_set_text(layout, result.description.ptr, @intCast(result.description.len));

                    c.cairo_set_source_rgb(cr, placeholder_r, placeholder_g, placeholder_b);

                    c.cairo_move_to(cr, text_left, item_y + 32.0);
                    c.pango_cairo_show_layout(cr, layout);
                }
            }
        }

        c.cairo_surface_flush(self.surface);
    }

    pub fn resizeWindow(self: *Renderer, conn: *c.xcb_connection_t, win: u32, result_count: usize) void {
        const new_height = utils.calcHeight(result_count);
        const values = [_]u32{@as(u32, new_height)};
        _ = c.xcb_configure_window(conn, win, c.XCB_CONFIG_WINDOW_HEIGHT, &values);
        c.cairo_xcb_surface_set_size(self.surface, self.width, @intCast(new_height));
        self.height = @intCast(new_height);
    }

    fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: f64) void {
        const pi = std.math.pi;
        c.cairo_new_sub_path(cr);
        c.cairo_arc(cr, x + w - r, y + r, r, -pi / 2.0, 0);
        c.cairo_arc(cr, x + w - r, y + h - r, r, 0, pi / 2.0);
        c.cairo_arc(cr, x + r, y + h - r, r, pi / 2.0, pi);
        c.cairo_arc(cr, x + r, y + r, r, pi, 3.0 * pi / 2.0);
        c.cairo_close_path(cr);
    }
};
