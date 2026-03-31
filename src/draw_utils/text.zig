const c = @import("../c.zig").c;
const Color = @import("../colors.zig").Color;

pub const TextSize = struct { w: i32, h: i32 };

/// Returns the rendered dimensions of text without drawing it.
pub fn measureText(cr: *c.cairo_t, text: []const u8, font_desc_str: []const u8) TextSize {
    const layout = c.pango_cairo_create_layout(cr) orelse return .{ .w = 0, .h = 0 };
    defer c.g_object_unref(layout);

    const fd = c.pango_font_description_from_string(font_desc_str.ptr);
    defer c.pango_font_description_free(fd);
    c.pango_layout_set_font_description(layout, fd);
    c.pango_layout_set_text(layout, text.ptr, @intCast(text.len));

    var text_w: c_int = 0;
    var text_h: c_int = 0;
    c.pango_layout_get_pixel_size(layout, &text_w, &text_h);

    return .{ .w = text_w, .h = text_h };
}

/// Draws text at (x, y) using the given font and color.
/// Returns the rendered text dimensions in pixels.
pub fn drawTextMeasured(cr: *c.cairo_t, text: []const u8, font_desc_str: []const u8, color: Color, x: f64, y: f64) TextSize {
    const layout = c.pango_cairo_create_layout(cr) orelse return .{ .w = 0, .h = 0 };
    defer c.g_object_unref(layout);

    const fd = c.pango_font_description_from_string(font_desc_str.ptr);
    defer c.pango_font_description_free(fd);
    c.pango_layout_set_font_description(layout, fd);
    c.pango_layout_set_text(layout, text.ptr, @intCast(text.len));

    c.cairo_set_source_rgb(cr, color.r, color.g, color.b);
    c.cairo_move_to(cr, x, y);
    c.pango_cairo_show_layout(cr, layout);

    var text_w: c_int = 0;
    var text_h: c_int = 0;
    c.pango_layout_get_pixel_size(layout, &text_w, &text_h);

    return .{ .w = text_w, .h = text_h };
}

/// Draws text at (x, y) using the given font and color.
/// Discards the rendered dimensions — use drawTextMeasured if you need them.
pub fn drawText(cr: *c.cairo_t, text: []const u8, font_desc_str: []const u8, color: Color, x: f64, y: f64) void {
    _ = drawTextMeasured(cr, text, font_desc_str, color, x, y);
}
