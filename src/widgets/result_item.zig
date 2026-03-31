const draw_shapes = @import("../draw_utils/shapes.zig");
const draw_text = @import("../draw_utils/text.zig");
const c = @import("../c.zig").c;
const constants = @import("../constants.zig");
const colors = @import("../colors.zig");
const Result = @import("../result.zig").Result;
const RenderContext = @import("../draw_utils/context.zig").RenderContext;

const selected_bg = colors.selected_bg;
const fg = colors.fg;
const unselected_fg = colors.unselected_fg;
const placeholder = colors.placeholder;

pub fn draw(result: *const Result, ctx: RenderContext, item_y: f64, icon: ?*c.cairo_surface_t) void {
    if (result.selected) {
        draw_shapes.roundedRect(ctx.cr, 6.0, item_y + 2.0, @as(f64, constants.WIN_WIDTH) - 12.0, constants.RESULT_ITEM_HEIGHT - 4.0, draw_shapes.Rounding.all(8.0));
        c.cairo_set_source_rgb(ctx.cr, selected_bg.r, selected_bg.g, selected_bg.b);
        c.cairo_fill(ctx.cr);
    }

    if (icon) |icon_surface| {
        const icon_x: f64 = 14.0;
        const icon_y: f64 = item_y + (constants.RESULT_ITEM_HEIGHT - @as(f64, @floatFromInt(constants.ICON_SIZE))) / 2.0;

        c.cairo_set_source_surface(ctx.cr, icon_surface, icon_x, icon_y);
        c.cairo_paint(ctx.cr);
    }

    const name_color = if (result.selected) fg else unselected_fg;
    draw_text.drawText(ctx.cr, result.name, ctx.font_desc_str, name_color, ctx.text_left, item_y + 8.0);
    draw_text.drawText(ctx.cr, result.description, ctx.font_desc_small_str, placeholder, ctx.text_left, item_y + 32.0);
}
