const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const DateTime = @import("../time.zig").DateTime;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const c = @import("../c.zig").c;
const Renderer = @import("../renderer.zig").Renderer;
const dtypes = @import("../draw_utils/types.zig");

const fg = colors.fg;
const month_names = constants.MONTH_NAMES;

pub const DateWidget = struct {
    date: ?DateTime,

    pub fn create() DateWidget {
        return .{
            .date = null,
        };
    }

    pub fn getId() []const u8 {
        return "date";
    }

    pub fn asWidget(self: *DateWidget) Widget {
        return .{
            .ctx = self,
            .draw = draw,
            .load = load,
            .unload = unload,
        };
    }

    fn draw(ctx: *anyopaque, renderer: *Renderer, y: f64, query: []const u8) void {
        _ = query;
        const self: *DateWidget = @ptrCast(@alignCast(ctx));
        const date = self.date orelse return;

        const icon_size: f64 = 36.0;
        const fold: f64 = 8.0;
        const icon_x: f64 = 16.0;
        const icon_y: f64 = y + (constants.WIDGET_HEIGHT - icon_size) / 2.0;

        // Calendar icon outline
        //c.cairo_set_line_width(cr, 1.5);
        //c.cairo_set_source_rgb(cr, fg.r, fg.g, fg.b);
        //c.cairo_move_to(cr, icon_x, icon_y);
        //c.cairo_line_to(cr, icon_x + icon_size, icon_y); // top
        //c.cairo_line_to(cr, icon_x + icon_size, icon_y + icon_size - fold); // right
        //c.cairo_line_to(cr, icon_x + icon_size - fold, icon_y + icon_size); // diagonal fold
        //c.cairo_line_to(cr, icon_x, icon_y + icon_size); // bottom
        //c.cairo_close_path(cr); // left
        //c.cairo_stroke(cr);
        renderer.drawStrokePath(1.5, true, fg, &[_]dtypes.Position{
            .{.x = icon_x, .y = icon_y},
            .{.x = icon_x + icon_size, .y = icon_y},
            .{.x = icon_x + icon_size, .y = icon_y + icon_size - fold},
            .{.x = icon_x + icon_size - fold, .y = icon_y + icon_size},
            .{.x = icon_x, .y = icon_y + icon_size},
        });

        // Day number centered inside the icon
        var day_buf: [2]u8 = undefined;
        const day_str = std.fmt.bufPrint(&day_buf, "{d}", .{date.day}) catch return;
        const day_size = renderer.measureText(day_str, .searchItemDesc);
        const day_x = icon_x + (icon_size - @as(f64, @floatFromInt(day_size.w))) / 2.0;
        const day_y = icon_y + (icon_size - @as(f64, @floatFromInt(day_size.h))) / 2.0;
        _ = renderer.drawText(day_str, .searchItemDesc, fg, day_x, day_y);

        // Date text
        const month_idx: usize = @intCast(date.month - 1);
        const month_name = if (month_idx < month_names.len) month_names[month_idx] else "???";

        var text_buf: [32]u8 = undefined;
        const date_str = std.fmt.bufPrint(&text_buf, "{d}. {s} {d}", .{ date.day, month_name, date.year }) catch return;

        const text_x = icon_x + icon_size + 12.0;
        const text_size = renderer.measureText(date_str, .searchItemTitle);
        const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(text_size.h))) / 2.0;
        _ = renderer.drawText(date_str, .searchItemTitle, fg, text_x, text_y);
    }

    fn load(ctx: *anyopaque) !void {
        const self: *DateWidget = @ptrCast(@alignCast(ctx));
        self.date = try DateTime.init();
    }

    fn unload(ctx: *anyopaque) !void {
        const self: *DateWidget = @ptrCast(@alignCast(ctx));
        self.date = null;
    }
};
