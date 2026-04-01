const std = @import("std");
const c = @import("c.zig").c;
const utils = @import("utils.zig");
const constants = @import("constants.zig");
const Result = @import("result.zig").Result;
const icon_mod = @import("icon.zig");
const colors = @import("colors.zig");
const draw_shapes = @import("draw_utils/shapes.zig");
const draw_text = @import("draw_utils/text.zig");
const RenderContext = @import("draw_utils/context.zig").RenderContext;
const result_item = @import("widgets/result_item.zig");
const SearchTag = @import("search.zig").SearchTag;

const Color = colors.Color;

pub const Renderer = struct {
    surface: *c.cairo_surface_t,
    cr: *c.cairo_t,
    width: u16,
    height: u16,

    const bg = colors.bg;
    const container_bg = colors.container_bg;
    const placeholder = colors.placeholder;
    const fg = colors.fg;
    const selected_bg = colors.selected_bg;

    const padding: f64 = 16.0;
    const search_chip_margin: f64 = 6.0;
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

    pub fn draw(self: *Renderer, search_text: []const u8, search_tag: SearchTag, results: []const Result, icons: *icon_mod.IconCache, cursor_visible: bool) void {
        const cr = self.cr;
        const width = self.width;
        const height = self.height;

        const render_tag_chip = search_tag != SearchTag.Unspecified;

        //c.cairo_set_source_rgb(cr, bg.r, bg.g, bg.b);
        //c.cairo_paint(cr);

        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(cr);
        c.cairo_set_operator(cr, c.CAIRO_OPERATOR_OVER);

        draw_shapes.roundedRect(cr, 0.0, 0.0, @as(f64, @floatFromInt(width)), @as(f64, @floatFromInt(height)), draw_shapes.Rounding.all(8.0));
        c.cairo_set_source_rgb(cr, bg.r, bg.g, bg.b);
        c.cairo_fill(cr);

        const margin: f64 = 6.0;
        const bar_x = margin;
        const bar_y = margin;
        const bar_w = @as(f64, @floatFromInt(width)) - margin * 2.0;
        const bar_h = constants.SEARCH_BAR_HEIGHT - margin * 2.0;
        const radius: f64 = 10.0;

        draw_shapes.roundedRect(cr, bar_x, bar_y, bar_w, bar_h, draw_shapes.Rounding.all(radius));
        c.cairo_set_source_rgb(cr, container_bg.r, container_bg.g, container_bg.b);
        c.cairo_fill(cr);

        var search_chip_width: f64 = 0;

        // SeachTag Chip
        if (render_tag_chip) {
            const chip_x = bar_x + search_chip_margin;
            const chip_y = bar_y + search_chip_margin;

            const c_padding: f64 = 4.0;
            const display_text = @tagName(search_tag);
            const txt_size = draw_text.measureText(cr, display_text, font_desc_str);

            search_chip_width = c_padding * 2 + @as(f64, @floatFromInt(txt_size.w));
            const c_height = bar_h - search_chip_margin * 2;

            const text_x = chip_x + c_padding;
            const text_y = chip_y + (c_height - @as(f64, @floatFromInt(txt_size.h))) / 2.0;

            draw_shapes.roundedRect(cr, chip_x, chip_y, search_chip_width, c_height, draw_shapes.Rounding.all(8.0));
            c.cairo_set_source_rgb(cr, bg.r, bg.g, bg.b);
            c.cairo_fill(cr);

            draw_text.drawText(cr, display_text, font_desc_str, fg, text_x, text_y);
        }

        // Text input field
        {
            const text_x = bar_x + padding + search_chip_width;
            const display_text = if (search_text.len == 0) "Search..." else search_text;
            const display_color = if (search_text.len == 0) placeholder else fg;

            const size = draw_text.measureText(cr, display_text, font_desc_str);
            const text_y = bar_y + (bar_h - @as(f64, @floatFromInt(size.h))) / 2.0;
            const text_w = draw_text.drawTextMeasured(cr, display_text, font_desc_str, display_color, text_x, text_y).w;

            if (cursor_visible) {
                const cursor_w = if (search_text.len == 0) -2 else text_w;
                c.cairo_set_source_rgb(cr, fg.r, fg.g, fg.b);
                const cursor_x = text_x + @as(f64, @floatFromInt(cursor_w)) + 2.0;
                const cursor_y = bar_y + 10.0;
                const cursor_h = bar_h - 20.0;
                c.cairo_rectangle(cr, cursor_x, cursor_y, 2.0, cursor_h);
                c.cairo_fill(cr);
            }
        }

        // Result list
        if (results.len > 0) {
            // Seperator line
            c.cairo_set_source_rgb(cr, selected_bg.r, selected_bg.g, selected_bg.b);
            c.cairo_rectangle(cr, 12.0, constants.SEARCH_BAR_HEIGHT - 1.0, @as(f64, constants.WIN_WIDTH) - 24.0, 1.0);
            c.cairo_fill(cr);

            const ctx = RenderContext{
                .cr = cr,
                .font_desc_str = font_desc_str,
                .font_desc_small_str = font_desc_small_str,
                .text_left = text_left,
            };

            for (results, 0..) |result, i| {
                const iy: f64 = @floatFromInt(i);
                const item_y = constants.SEARCH_BAR_HEIGHT + iy * constants.RESULT_ITEM_HEIGHT;
                result_item.draw(&result, ctx, item_y, icons.get(result.icon_name));
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
};
