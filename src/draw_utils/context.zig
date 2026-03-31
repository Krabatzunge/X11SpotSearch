const c = @import("../c.zig").c;

pub const RenderContext = struct {
    cr: *c.cairo_t,
    font_desc_str: []const u8,
    font_desc_small_str: []const u8,
    text_left: f64,
};
