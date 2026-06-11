const std = @import("std");
const Renderer = @import("../renderer.zig").Renderer;

pub const Widget = struct {
    ctx: *anyopaque,
    draw: *const fn (ctx: *anyopaque, renderer: *Renderer, y: f64, query: []const u8) void,
    load: *const fn (ctx: *anyopaque) anyerror!void,
    unload: *const fn (ctx: *anyopaque) anyerror!void,
};
