const Color = @import("../colors.zig").Color;

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

pub const BorderType = enum {
    Inner,
    Outer,
    None,
};

pub const Border = struct {
    rounding: Rounding,
    color: Color, 
    width: f64,
    btype: BorderType,

    pub const None: Border = .{.rounding = Rounding.all(0.0), .color = Color.rgb(0, 0, 0), .btype = .None, .width = 0.0};

    pub fn all(width: f64, color: Color, rounding: Rounding, btype: BorderType) Border {
        return .{.rounding = rounding, .color = color, .width = width, .btype = btype};
    }
};
