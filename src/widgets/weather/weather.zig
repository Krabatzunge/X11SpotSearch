const std = @import("std");
const assets = @import("../../assets.zig");
const ParsedWeather = @import("../../network/parsers/weather.zig").Weather;

pub const Weather = struct {
    units: Units,
    current: Current,

    pub const Units = struct {
        temperature: []const u8,
        wind_speed: []const u8,
        wind_direction: []const u8,
        weather_code: []const u8,
    };

    pub const Current = struct {
        time: []const u8,
        temperature: f32,
        wind_speed: f32,
        wind_direction: i32,
        is_day: bool,
        weather_code: i32,
    };

    pub fn initFromParsed(parsed: ParsedWeather) Weather {
        return .{
            .units = .{
                .temperature = parsed.current_weather_units.temperature,
                .wind_speed = parsed.current_weather_units.windspeed,
                .wind_direction = parsed.current_weather_units.winddirection,
                .weather_code = parsed.current_weather_units.weathercode,
            },
            .current = .{
                .time = parsed.current_weather.time,
                .temperature = parsed.current_weather.temperature,
                .wind_speed = parsed.current_weather.windspeed,
                .wind_direction = parsed.current_weather.winddirection,
                .is_day = parsed.current_weather.is_day != 0,
                .weather_code = parsed.current_weather.weathercode,
            },
        };
    }

    pub fn getIcon(self: @This()) assets.Icons {
        return iconFromWeatherCode(self.current.weather_code);
    }

    pub fn iconFromWeatherCode(weather_code: i32) assets.Icons {
        return switch (weather_code) {
            0 => .WeatherSun,
            1, 2, 3 => .WeatherCloudy,
            45, 48 => .WeatherFog,
            51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82 => .WeatherRain,
            71, 73, 75, 77, 85, 86 => .WeatherSnow,
            95, 96, 99 => .WeatherThunder,
            else => .WeatherCloudy,
        };
    }

    pub fn print(self: @This()) void {
        std.debug.print(
            "Current weather at {s}: temperature={d}{s}, wind_speed={d}{s}, wind_direction={}{s}, is_day={}, weather_code={}{s}\n",
            .{
                self.current.time,
                self.current.temperature,
                self.units.temperature,
                self.current.wind_speed,
                self.units.wind_speed,
                self.current.wind_direction,
                self.units.wind_direction,
                self.current.is_day,
                self.current.weather_code,
                self.units.weather_code,
            },
        );
    }
};
