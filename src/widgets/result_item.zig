const draw_shapes = @import("../draw_utils/shapes.zig");
const dtypes = @import("../draw_utils/types.zig");
const draw_text = @import("../draw_utils/text.zig");
const c = @import("../c.zig").c;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const Result = @import("../result.zig").Result;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;
const cattpuccin = @import("../themes/cattpuccin.zig");

const selected_bg = cattpuccin.surface1;
const fg = colors.fg;
const unselected_fg = colors.unselected_fg;
const placeholder = colors.placeholder;

pub fn draw(result: *const Result, ctx: RenderContext, item_y: f64, icon: ?*c.cairo_surface_t) void {
    if (result.selected) {
        draw_shapes.roundedRect(ctx.cr, 8.0, item_y + 2.0, @as(f64, constants.WIN_WIDTH) - 16.0, constants.RESULT_ITEM_HEIGHT - 4.0, dtypes.Rounding.all(12.0));
        c.cairo_set_source_rgb(ctx.cr, selected_bg.r, selected_bg.g, selected_bg.b);
        c.cairo_fill(ctx.cr);
    }

    if (icon) |icon_surface| {
        const icon_x: f64 = 16.0;
        const icon_y: f64 = item_y + (constants.RESULT_ITEM_HEIGHT - @as(f64, @floatFromInt(constants.ICON_SIZE))) / 2.0;

        c.cairo_set_source_surface(ctx.cr, icon_surface, icon_x, icon_y);
        c.cairo_paint(ctx.cr);
    }

    const name_color = if (result.selected) cattpuccin.text else cattpuccin.subtext1;
    draw_text.drawText(ctx.cr, result.name, RenderContext.font(.searchItemTitle), name_color, ctx.text_left + 2, item_y + 6.0);
    draw_text.drawText(ctx.cr, result.description, RenderContext.font(.searchItemDesc), cattpuccin.subtext0, ctx.text_left + 2, item_y + 32.0);
}
