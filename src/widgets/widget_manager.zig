const std = @import("std");
const Widget = @import("widget_struct.zig").Widget;
const Detector = @import("detector.zig").Detector;
const KeywordDetector = @import("detector.zig").KeywordDetector;
const DateWidget = @import("date_widget.zig").DateWidget;
const TimeWidget = @import("time_widget.zig").TimeWidget;
const CalcWidget = @import("calc_widget.zig").CalcWidget;
const CalcDetector = @import("calc_widget.zig").CalcDetector;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;

const WidgetEntry = struct {
    detector: Detector,
    widget: Widget,
};

pub const WidgetManager = struct {
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    entries: []WidgetEntry,

    active_widget: ?Widget,

    pub fn init(allocator: std.mem.Allocator) !WidgetManager {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();

        const date_ptr = try alloc.create(DateWidget);
        date_ptr.* = DateWidget.create();
        const date_det = try alloc.create(KeywordDetector);
        date_det.* = KeywordDetector.create(DateWidget.getId());

        const time_ptr = try alloc.create(TimeWidget);
        time_ptr.* = TimeWidget.create();
        const time_det = try alloc.create(KeywordDetector);
        time_det.* = KeywordDetector.create(TimeWidget.getId());

        const calc_ptr = try alloc.create(CalcWidget);
        calc_ptr.* = CalcWidget.create();
        const calc_det = try alloc.create(CalcDetector);
        calc_det.* = CalcDetector.create();

        const entries = try alloc.alloc(WidgetEntry, 3);
        entries[0] = .{ .detector = date_det.asDetector(), .widget = date_ptr.asWidget() };
        entries[1] = .{ .detector = time_det.asDetector(), .widget = time_ptr.asWidget() };
        entries[2] = .{ .detector = calc_det.asDetector(), .widget = calc_ptr.asWidget() };

        return .{
            .arena = arena,
            .allocator = allocator,
            .entries = entries,
            .active_widget = null,
        };
    }

    pub fn deinit(self: *WidgetManager) void {
        self.arena.deinit();
    }

    pub fn determineWidget(self: *WidgetManager, query: []const u8) void {
        const previous_widget = self.active_widget;
        self.active_widget = null;

        for (self.entries) |entry| {
            if (entry.detector.matches(entry.detector.ctx, query)) {
                self.active_widget = entry.widget;
            }
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
};
