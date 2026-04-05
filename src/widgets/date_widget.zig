const Widget = @import("widget_struct.zig").Widget;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;
const DateTime = @import("../time.zig").DateTime;

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

    fn draw(ctx: *anyopaque, render_ctx: RenderContext, y: f64) void {
        const self: *DateWidget = @ptrCast(@alignCast(ctx));

        _ = self;
        _ = render_ctx;
        _ = y;
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
