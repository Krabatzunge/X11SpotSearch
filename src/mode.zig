const std = @import("std");

pub const Mode = enum { oneshot, daemon };

pub const Config = struct {
    mode: Mode,
    hotkey_mod: u16, // X11 modifier mask (default Mod4 = Super)
    hotkey_keycode: u8, // X11 keycode for trigger key

    pub fn parse() Config {
        var config = Config{
            .mode = .oneshot,
            .hotkey_mod = 0x40, // Mod4Mask (Super key)
            .hotkey_keycode = 65, // space (keycode 65 on most X11)
        };

        var args = std.process.args();
        _ = args.skip();

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--deamon") or std.mem.eql(u8, arg, "-d")) {
                config.mode = .daemon;
            }
        }

        return config;
    }
};
