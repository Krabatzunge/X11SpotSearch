pub const Color = struct {
    r: f64,
    g: f64,
    b: f64,

    pub fn rgb_f(r: f64, g: f64, b: f64) Color {
        return .{
            .r = r / 255.0,
            .g = g / 255.0,
            .b = b / 255.0,
        };
    }

    pub fn rgb(r: u32, g: u32, b: u32) Color {
        return .{
            .r = @as(f64, r) / 255.0,
            .g = @as(f64, g) / 255.0,
            .b = @as(f64, b) / 255.0,
        };
    }
};
