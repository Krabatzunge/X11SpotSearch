const c = @import("../c.zig").c;

pub const Config = struct {
    loc: Location,
    hotkey_mod: u16, // X11 modifier mask (default Mod4 = Super)
    hotkey_keysym: u32, // XKB keysym for trigger key

    pub fn default() Config {
        return .{
            .loc = Location.default(),
            .hotkey_mod = 0x40, // Mod4Mask (Super key)
            .hotkey_keysym = c.XKB_KEY_space,
        };
    }
};

pub const Location = struct {
    lang: ?[]const u8,
    lon: ?f32,
    lat: ?f32,
    city: ?[]const u8,

    pub fn default() Location {
        return .{
            .lang = null,
            .lon = null,
            .lat = null,
            .city = null,
        };
    }
};
