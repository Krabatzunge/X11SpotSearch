const std = @import("std");
const assets = @import("assets.zig");

pub const WIN_WIDTH: u16 = 600;
//const WIN_HEIGHT: u16 = 60;
pub const SEARCH_BAR_HEIGHT: f64 = 60.0;
pub const RESULT_ITEM_HEIGHT: f64 = 56.0;
pub const MAX_RESULTS: usize = 5;

pub const ICON_SIZE: u16 = 32;

pub const CURSOR_BLINK_MS: u32 = 500;
pub const FRAME_MS: u32 = 16;

pub const MAIN_CATEGORIES = std.StaticStringMap(assets.Icons).initComptime(.{
    .{ "AudioVideo", .DefCatMedia },
    .{ "Audio", .DefCatMedia },
    .{ "Video", .DefCatMedia },
    .{ "Development", .DefCatDevelopment },
    .{ "Education", .DefCatEducation },
    .{ "Game", .DefCatGame },
    .{ "Graphics", .DefCatGraphics },
    .{ "Network", .DefCatNetwork },
    .{ "Office", .DefCatOffice },
    .{ "Science", .DefCatScience },
    .{ "Settings", .DefCatSettings },
    .{ "System", .DefCatSystem },
    .{ "Utility", .DefCatUtility },
});
pub const DEFAULT_APPLICATION_ICON = assets.Icons.DefaultApplication;
