const std = @import("std");

pub const Weather = struct {
    latitude: f32,
    longitude: f32,
    generationtime_ms: f32,
    utc_offset_seconds: i32,
    timezone: []const u8,
    timezone_abbreviation: []const u8,
    elevation: f32,
    current_weather_units: Units,
    current_weather: Current,

    pub const Units = struct {
        time: []const u8,
        interval: []const u8,
        temperature: []const u8,
        windspeed: []const u8,
        winddirection: []const u8,
        is_day: []const u8,
        weathercode: []const u8,
    };

    pub const Current = struct {
        time: []const u8,
        interval: u32,
        temperature: f32,
        windspeed: f32,
        winddirection: i32,
        is_day: i32,
        weathercode: i32,
    };
};

pub fn extract_weather(allocator: std.mem.Allocator, text: []const u8) !Weather {
    return std.json.parseFromSliceLeaky(Weather, allocator, text, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    }) catch return error.FailedToParseJson;
}
