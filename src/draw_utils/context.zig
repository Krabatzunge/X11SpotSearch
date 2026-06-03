const c = @import("../c.zig").c;
const IconModule = @import("../icons/icon.zig").IconModule;
const text = @import("text.zig");

pub const RenderContext = struct {
    cr: *c.cairo_t,
    font_desc_str: []const u8,
    font_desc_small_str: []const u8,
    text_left: f64,
    icon_mod: *IconModule,

    pub fn font(role: text.TextRole) []const u8 {
        return text.roleToFont(role);
    }
};
