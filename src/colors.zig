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

pub const bg: Color = Color.rgb_f(0x1e.0, 0x1e.0, 0x2e.0);

pub const fg: Color = Color.rgb(0xcd, 0xd6, 0xf4);

pub const placeholder: Color = Color.rgb(0x6c, 0x70, 0x86);

pub const container_bg: Color = Color.rgb(0x31, 0x31, 0x44);

pub const selected_bg: Color = Color.rgb(0x45, 0x47, 0x5a);
pub const unselected_fg: Color = Color.rgb(0xba, 0xc2, 0xde);
