const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;
const draw_text = @import("../draw_utils/text.zig");
const DateTime = @import("../time.zig").DateTime;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const c = @import("../c.zig").c;

const fg = colors.fg;
const fg2 = colors.placeholder;
const month_names = constants.MONTH_NAMES;

pub const TimeWidget = struct {
    pub fn create() TimeWidget {
        return .{};
    }

    pub fn getId() []const u8 {
        return "time";
    }

    pub fn asWidget(self: *TimeWidget) Widget {
        return .{
            .ctx = self,
            .draw = draw,
            .load = load,
            .unload = unload,
        };
    }

    fn draw(ctx: *anyopaque, render_ctx: RenderContext, y: f64) void {
        const self: *TimeWidget = @ptrCast(@alignCast(ctx));
        _ = self;
        const date = DateTime.init() catch return;

        const cr = render_ctx.cr;
        const clock_size: f64 = 36.0;
        const clock_x: f64 = 16.0;
        const clock_y: f64 = y + (constants.WIDGET_HEIGHT - clock_size) / 2.0;
        const clock_center_x = clock_x + clock_size / 2;
        const clock_center_y = clock_y + clock_size / 2;

        // Calendar icon outline
        c.cairo_set_line_width(cr, 1.5);
        c.cairo_set_source_rgb(cr, fg.r, fg.g, fg.b);
        c.cairo_arc(cr, clock_center_x, clock_center_y, clock_size / 2, 0, 2 * std.math.pi);
        c.cairo_stroke(cr);

        // Hour
        const hour_len = 14.0;
        c.cairo_set_line_width(cr, 1.4);
        c.cairo_set_source_rgb(cr, fg2.r, fg2.g, fg2.b);

        const hour_dec: f64 = @as(f64, @floatFromInt(@mod(date.hour, 12))) / 12.0 * 2.0 * std.math.pi;
        const hour_x = clock_center_x + std.math.sin(hour_dec) * hour_len;
        const hour_y = clock_center_y - std.math.cos(hour_dec) * hour_len;
        c.cairo_move_to(cr, clock_center_x, clock_center_y);
        c.cairo_line_to(cr, hour_x, hour_y);
        c.cairo_stroke(cr);

        // Minutes
        const minute_len = 16.0;
        c.cairo_set_line_width(cr, 1.25);
        const minute_dec: f64 = @as(f64, @floatFromInt(date.minute)) / 60.0 * 2.0 * std.math.pi;
        const minute_x = clock_center_x + std.math.sin(minute_dec) * minute_len;
        const minute_y = clock_center_y - std.math.cos(minute_dec) * minute_len;
        c.cairo_move_to(cr, clock_center_x, clock_center_y);
        c.cairo_line_to(cr, minute_x, minute_y);
        c.cairo_stroke(cr);

        // Time text
        var text_buf: [8]u8 = undefined;
        const date_str = std.fmt.bufPrint(&text_buf, "{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(date.hour)), @as(u32, @intCast(date.minute)) }) catch return;

        const text_x = clock_x + clock_size + 12.0;
        const text_size = draw_text.measureText(cr, date_str, render_ctx.font_desc_str);
        const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(text_size.h))) / 2.0;
        draw_text.drawText(cr, date_str, render_ctx.font_desc_str, fg, text_x, text_y);
    }

    fn load(ctx: *anyopaque) !void {
        const self: *TimeWidget = @ptrCast(@alignCast(ctx));
        _ = self;
    }

    fn unload(ctx: *anyopaque) !void {
        const self: *TimeWidget = @ptrCast(@alignCast(ctx));
        _ = self;
    }
};
