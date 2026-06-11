const std = @import("std");
const c = @import("c.zig").c;
const utils = @import("utils.zig");
const constants = @import("constants.zig");
const Result = @import("result.zig").Result;
const icon_mod = @import("icons/icon.zig");
const colors = @import("colors.zig");
const draw_shapes = @import("draw_utils/shapes.zig");
const dtypes = @import("draw_utils/types.zig");
const draw_text = @import("draw_utils/text.zig");
const RenderContext = @import("draw_utils/context.zig").RenderContext;
const result_item = @import("widgets/result_item.zig");
const Widget = @import("widgets/widget_struct.zig").Widget;
const SearchTag = @import("search.zig").SearchTag;
const Icons = @import("assets.zig").Icons;
const cattpuccin = @import("themes/cattpuccin.zig");

const Color = colors.Color;

pub const Renderer = struct {
    back_surface: *c.cairo_surface_t,
    back_cr: *c.cairo_t,
    width: u16,
    height: u16,
    iconMod: *icon_mod.IconModule,

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

    pub fn init(width: u16, height: u16, iconMod: *icon_mod.IconModule) !Renderer {
        const max_height: c_int = @intCast(utils.calcHeight(constants.MAX_RESULTS, true));

        const back_surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, width, max_height) orelse return error.CairoSurfaceFailed;
        errdefer c.cairo_surface_destroy(back_surface);
        const back_cr = c.cairo_create(back_surface) orelse return error.CairoCreateFailed;

        const font_opts = c.cairo_font_options_create();
        defer c.cairo_font_options_destroy(font_opts);
        c.cairo_font_options_set_antialias(font_opts, c.CAIRO_ANTIALIAS_SUBPIXEL);
        c.cairo_set_font_options(back_cr, font_opts);

        return .{ .width = width, .height = height, .back_surface = back_surface, .back_cr = back_cr, .iconMod = iconMod };
    }

    pub fn deinit(self: *Renderer) void {
        c.cairo_destroy(self.back_cr);
        c.cairo_surface_destroy(self.back_surface);
    }

    pub fn beginFrame(self: *Renderer) void {
        c.cairo_set_operator(self.back_cr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgba(self.back_cr, 0.0, 0.0, 0.0, 0.0);
        c.cairo_paint(self.back_cr);
        c.cairo_set_operator(self.back_cr, c.CAIRO_OPERATOR_OVER);
    }

    pub fn endFrame(self: *Renderer, targetCr: ?*c.cairo_t) void {
        c.cairo_surface_flush(self.back_surface);
        c.cairo_set_operator(targetCr, c.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_surface(targetCr, self.back_surface, 0, 0);
        c.cairo_paint(targetCr);
        c.cairo_surface_flush(c.cairo_get_target(targetCr));
    }
 
    pub fn resizeWindow(self: *Renderer, conn: *c.xcb_connection_t, win: u32, result_count: usize, has_widget: bool) void {
        const new_height = utils.calcHeight(result_count, has_widget);
        const values = [_]u32{@as(u32, new_height)};
        _ = c.xcb_configure_window(conn, win, c.XCB_CONFIG_WINDOW_HEIGHT, &values);
        self.height = @intCast(new_height);
    }

    // Render function
    pub fn drawRectangle(self: *Renderer, x: f64, y: f64, w: f64, h: f64, col: Color, r: dtypes.Rounding, b: dtypes.Border) void {
        draw_shapes.roundedRect(self.back_cr, x, y, w, h, r);
        c.cairo_set_source_rgb(self.back_cr, col.r, col.g, col.b);
        c.cairo_fill(self.back_cr);

        if (b.btype != .None) {
            const bw_f = b.width;
            const off: f64 = switch (b.btype) {
                .Inner => bw_f / 2.0,
                .Outer => -bw_f / 2.0,
                .None => 0.0,
            };

            const bx = x + off;
            const by = y + off;
            const bw = @max(w - off * 2.0, 0);
            const bh = @max(h - off * 2.0, 0);

            const rounding = adjustRounding(b.rounding, -off);

            draw_shapes.roundedRect(self.back_cr, bx, by, bw, bh, rounding);
            c.cairo_set_source_rgb(self.back_cr, b.color.r, b.color.g, b.color.b);
            c.cairo_set_line_width(self.back_cr, bw_f);
            c.cairo_stroke(self.back_cr);
        }
    }

    fn adjustRounding(rounding: dtypes.Rounding, delta: f64) dtypes.Rounding {
        return .{
            .top_left = @max(rounding.top_left + delta, 0),
            .top_right = @max(rounding.top_right + delta, 0),
            .bottom_left = @max(rounding.bottom_left + delta, 0),
            .bottom_right = @max(rounding.bottom_right + delta, 0),
        };
    }

    pub fn drawStrokePath(self: *Renderer, width: f64, closePath: bool, color: Color, pos: []const dtypes.Position) void {
        c.cairo_set_line_width(self.back_cr, width);
        c.cairo_set_source_rgb(self.back_cr, color.r, color.g, color.b);
        c.cairo_move_to(self.back_cr, pos[0].x, pos[0].y);

        for (pos[1..]) |p| {
            c.cairo_line_to(self.back_cr, p.x, p.y);
        }

        if (closePath) c.cairo_close_path(self.back_cr);

        c.cairo_stroke(self.back_cr);
    }

    pub fn drawStrokeArc(self: *Renderer, swidth: f64, color: Color, center: dtypes.Position, radius: f64, offset: f64, progress: f64) void {
        c.cairo_set_line_width(self.back_cr, swidth);
        c.cairo_set_source_rgb(self.back_cr, color.r, color.g, color.b);
        c.cairo_arc(self.back_cr, center.x, center.y, radius, offset, progress);
        c.cairo_stroke(self.back_cr);
    }
    
    pub fn drawText(self: *Renderer, text: []const u8, font: draw_text.TextRole, color: Color, x: f64, y: f64) draw_text.TextSize {
        return draw_text.drawTextMeasured(self.back_cr, text, draw_text.roleToFont(font), color, x, y);
    }

    pub fn measureText(self: *Renderer, text: []const u8, font: draw_text.TextRole) draw_text.TextSize {
        return draw_text.measureText(self.back_cr, text, draw_text.roleToFont(font));
    }

    // TODO: add draw icon method
};
