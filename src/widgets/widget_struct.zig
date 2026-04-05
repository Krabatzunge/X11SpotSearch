const std = @import("std");
const RenderContext = @import("../draw_utils/context.zig").RenderContext;

pub const Widget = struct {
    ctx: *anyopaque,
    draw: *const fn (ctx: *anyopaque, render_ctx: RenderContext, y: f64) void,
    load: *const fn (ctx: *anyopaque) anyerror!void,
    unload: *const fn (ctx: *anyopaque) anyerror!void,
};
