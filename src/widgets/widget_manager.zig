const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const DateWidget = @import("date_widget.zig").DateWidget;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;

pub const WidgetManager = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    widget_map: std.StringHashMap(Widget),

    active_widget: ?Widget,

    // Widgets
    date: *DateWidget,

    pub fn init(allocator: std.mem.Allocator) !WidgetManager {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();
        var map = std.StringHashMap(Widget).init(allocator);

        const date_ptr = try alloc.create(DateWidget);
        date_ptr.* = DateWidget.create();
        try map.put(DateWidget.getId(), date_ptr.asWidget());

        return .{
            .arena = arena,
            .allocator = allocator,
            .widget_map = map,
            .active_widget = null,
            .date = date_ptr,
        };
    }

    pub fn deinit(self: *WidgetManager) void {
        self.widget_map.deinit();
        self.arena.deinit();
    }

    pub fn determineWidget(self: *WidgetManager, query: []const u8) void {
        //TODO: add $ starting search testing
        const previous_widget = self.active_widget;
        self.active_widget = null;
        var iter = std.mem.tokenizeScalar(u8, query, ' ');

        while (iter.next()) |word| {
            var buf: [64]u8 = undefined;
            if (word.len > buf.len) continue;
            const lower = std.ascii.lowerString(buf[0..word.len], word);
            self.active_widget = self.widget_map.get(lower) orelse continue;
            std.debug.print("Found widget {s}", .{lower});
        }

        const prev_ctx: ?*anyopaque = if (previous_widget) |w| w.ctx else null;
        const next_ctx: ?*anyopaque = if (self.active_widget) |w| w.ctx else null;

        if (prev_ctx != next_ctx) {
            if (previous_widget) |w| {
                w.unload(w.ctx) catch |err| std.log.err("widget unload failed: {}", .{err});
            }
            if (self.active_widget) |w| {
                w.load(w.ctx) catch |err| std.log.err("widget load failed: {}", .{err});
            }
        }
    }

    //pub fn draw(self: *WidgetManager, render_ctx: RenderContext, y: f64) void {
    //    if (self.active_widget) |widget| {
    //        widget.draw(widget.ctx, render_ctx, y);
    //    }
    //}
};
