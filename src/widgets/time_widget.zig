const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const DateTime = @import("../time.zig").DateTime;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const c = @import("../c.zig").c;
const Renderer = @import("../renderer.zig").Renderer;
const dtypes = @import("../draw_utils/types.zig");

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

    fn draw(ctx: *anyopaque, renderer: *Renderer, y: f64, query: []const u8) void {
        _ = query;
        const self: *TimeWidget = @ptrCast(@alignCast(ctx));
        _ = self;
        const date = DateTime.init() catch return;

        const clock_size: f64 = 36.0;
        const clock_x: f64 = 16.0;
        const clock_y: f64 = y + (constants.WIDGET_HEIGHT - clock_size) / 2.0;
        const clock_center: dtypes.Position = .{ .x = clock_x + clock_size / 2, .y = clock_y + clock_size / 2};

        // Calendar icon outline
        //c.cairo_set_line_width(cr, 1.5);
        //c.cairo_set_source_rgb(cr, fg.r, fg.g, fg.b);
        //c.cairo_arc(cr, clock_center_x, clock_center_y, clock_size / 2, 0, 2 * std.math.pi);
        //c.cairo_stroke(cr);
        renderer.drawStrokeArc(1.5, fg, clock_center, clock_size / 2, 0, 2 * std.math.pi);

        // Hour
        const hour_len = 14.0;
        //c.cairo_set_line_width(cr, 1.4);
        //c.cairo_set_source_rgb(cr, fg2.r, fg2.g, fg2.b);

        const hour_dec: f64 = @as(f64, @floatFromInt(@mod(date.hour, 12))) / 12.0 * 2.0 * std.math.pi;
        const hour_x = clock_center.x + std.math.sin(hour_dec) * hour_len;
        const hour_y = clock_center.y - std.math.cos(hour_dec) * hour_len;
        const hourPos: dtypes.Position = .{.x = hour_x, .y = hour_y};
        //c.cairo_move_to(cr, clock_center_x, clock_center_y);
        //c.cairo_line_to(cr, hour_x, hour_y);
        //c.cairo_stroke(cr);
        renderer.drawStrokePath(1.4, false, fg2, &[_]dtypes.Position{clock_center, hourPos,});

        // Minutes
        const minute_len = 16.0;
        //c.cairo_set_line_width(cr, 1.25);
        const minute_dec: f64 = @as(f64, @floatFromInt(date.minute)) / 60.0 * 2.0 * std.math.pi;
        const minute_x = clock_center.x + std.math.sin(minute_dec) * minute_len;
        const minute_y = clock_center.y - std.math.cos(minute_dec) * minute_len;
        const minutePos: dtypes.Position = .{.x = minute_x, .y = minute_y};
        //c.cairo_move_to(cr, clock_center_x, clock_center_y);
        //c.cairo_line_to(cr, minute_x, minute_y);
        //c.cairo_stroke(cr);
        renderer.drawStrokePath(1.25, false, fg2, &[_]dtypes.Position{clock_center, minutePos});

        // Time text
        var text_buf: [8]u8 = undefined;
        const date_str = std.fmt.bufPrint(&text_buf, "{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(date.hour)), @as(u32, @intCast(date.minute)) }) catch return;

        const text_x = clock_x + clock_size + 12.0;
        const text_size = renderer.measureText(date_str, .searchItemTitle);
        const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(text_size.h))) / 2.0;
        _ = renderer.drawText(date_str, .searchItemTitle, fg, text_x, text_y);
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
