const std = @import("std");
const c = @import("../c.zig").c;

pub const Rounding = struct {
    top_left: f64,
    top_right: f64,
    bottom_left: f64,
    bottom_right: f64,

    pub fn all(r: f64) Rounding {
        return .{
            .top_left = r,
            .bottom_left = r,
            .bottom_right = r,
            .top_right = r,
        };
    }

    pub fn single(tlr: f64, trr: f64, blr: f64, brr: f64) Rounding {
        return .{
            .top_left = tlr,
            .top_right = trr,
            .bottom_left = blr,
            .bottom_right = brr,
        };
    }

    pub fn top(r: f64) Rounding {
        return .{
            .top_left = r,
            .top_right = r,
            .bottom_left = 0.0,
            .bottom_right = 0.0,
        };
    }

    pub fn bottom(r: f64) Rounding {
        return .{
            .top_left = 0.0,
            .top_right = 0.0,
            .bottom_left = r,
            .bottom_right = r,
        };
    }

    pub fn left(r: f64) Rounding {
        return .{
            .top_left = r,
            .top_right = 0.0,
            .bottom_left = r,
            .bottom_right = 0.0,
        };
    }
    pub fn right(r: f64) Rounding {
        return .{
            .top_left = 0.0,
            .top_right = r,
            .bottom_left = 0.0,
            .bottom_right = r,
        };
    }
};

pub fn roundedRect(cr: *c.cairo_t, x: f64, y: f64, w: f64, h: f64, r: Rounding) void {
    const pi = std.math.pi;
    c.cairo_new_sub_path(cr);
    c.cairo_arc(cr, x + w - r.top_right, y + r.top_right, r.top_right, -pi / 2.0, 0.0);
    c.cairo_arc(cr, x + w - r.bottom_right, y + h - r.bottom_right, r.bottom_right, 0.0, pi / 2.0);
    c.cairo_arc(cr, x + r.bottom_left, y + h - r.bottom_left, r.bottom_left, pi / 2.0, pi);
    c.cairo_arc(cr, x + r.top_left, y + r.top_left, r.top_left, pi, 3.0 * pi / 2.0);
    c.cairo_close_path(cr);
}
