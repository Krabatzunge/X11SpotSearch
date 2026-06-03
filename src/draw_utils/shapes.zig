const std = @import("std");
const c = @import("../c.zig").c;
const dtypes = @import("types.zig");

pub fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: dtypes.Rounding) void {
    const pi = std.math.pi;
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - r.top_right, y + r.top_right, r.top_right, -pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - r.bottom_right, y + h - r.bottom_right, r.bottom_right, 0.0, pi / 2.0);
    c.cairo_arc(cr, x + r.bottom_left, y + h - r.bottom_left, r.bottom_left, pi / 2.0, pi);
    c.cairo_arc(cr, x + r.top_left, y + r.top_left, r.top_left, pi, 3.0 * pi / 2.0);
    c.cairo_close_path(cr);
}
