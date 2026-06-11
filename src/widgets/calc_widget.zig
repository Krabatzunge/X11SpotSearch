const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const Detector = @import("detector.zig").Detector;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const c = @import("../c.zig").c;
const expression_parser = @import("../utils/expression_parser.zig");
const draw_text = @import("../draw_utils/text.zig");
const Colors = @import("../colors.zig");
const Renderer = @import("../renderer.zig").Renderer;

const fg = Colors.fg;
const sfg = Colors.placeholder;

pub const CalcDetector = struct {
    pub fn create() CalcDetector {
        return .{};
    }

    pub fn asDetector(self: *CalcDetector) Detector {
        return .{
            .ctx = self,
            .matches = matches,
        };
    }

    fn matches(ctx: *anyopaque, query: []const u8) bool {
        _ = ctx;
        for (query) |chr| {
            switch (chr) {
                // Digits, basic math operators, parentheses, and spaces
                '0'...'9', '+', '-', '*', '/', '(', ')', ' ' => {},
                else => return false,
            }
        }
        return true;
    }
};

pub const CalcWidget = struct {
    pub fn create() CalcWidget {
        return .{};
    }

    pub fn asWidget(self: *CalcWidget) Widget {
        return .{
            .ctx = self,
            .draw = draw,
            .load = load,
            .unload = unload,
        };
    }

    fn draw(ctx: *anyopaque, renderer: *Renderer, y: f64, query: []const u8) void {
        _ = ctx;

        const expression: ?f64 = expression_parser.evaluate(query) catch null;
        const padding_x: f64 = 16.0;

        var exp_x = padding_x;

        if (expression) |exp| {
            var result_buf: [22]u8 = undefined;
            const exp_result = std.fmt.bufPrint(&result_buf, "{d} =", .{exp}) catch "";
            const txt_size = renderer.measureText(exp_result, .searchItemTitle);
            const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(txt_size.h))) / 2.0;
            _ = renderer.drawText(exp_result, .searchItemTitle, fg, padding_x, text_y);
            exp_x = exp_x + @as(f64, @floatFromInt(txt_size.w)) + 4.0;
        }

        {
            const txt_size = renderer.measureText(query, .searchItemDesc);
            const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(txt_size.h))) / 2.0;
            _ = renderer.drawText(query, .searchItemDesc, sfg, exp_x, text_y);
        }
    }

    fn load(ctx: *anyopaque) !void {
        _ = ctx;
    }

    fn unload(ctx: *anyopaque) !void {
        _ = ctx;
    }
};
