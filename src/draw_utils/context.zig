const c = @import("../c.zig").c;
const IconModule = @import("../icons/icon.zig").IconModule;
const text = @import("text.zig");

pub const RenderContext = struct {
    cr: *c.cairo_t,
    text_left: f64,
};
