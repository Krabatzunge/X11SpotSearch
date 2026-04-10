const std = @import("std");
const Widget = @import("../widget_struct.zig").Widget;
const RenderContext = @import("../../draw_utils/context.zig").RenderContext;
const draw_text = @import("../../draw_utils/text.zig");
const constants = @import("../../constants.zig");
const colors = @import("../../colors.zig");
const c = @import("../../c.zig").c;
const Weather = @import("weather.zig").Weather;
const network = @import("../../network.zig");
const Location = @import("../../config/config.zig").Location;
const weather_extract = @import("../../network/parsers/weather.zig");
const Icons = @import("../../assets.zig").Icons;

const fg = colors.fg;

pub const WeatherWidget = struct {
    weather: ?Weather,
    net: *network.AsyncCurl,
    weather_req: ?*network.CurlRequest,
    loc: *Location,
    alloc: std.mem.Allocator,

    pub fn create(net: *network.AsyncCurl, location: *Location, alloc: std.mem.Allocator) WeatherWidget {
        return .{
            .weather = null,
            .net = net,
            .weather_req = null,
            .loc = location,
            .alloc = alloc,
        };
    }

    pub fn getId() []const u8 {
        return "weather";
    }

    pub fn asWidget(self: *WeatherWidget) Widget {
        return .{
            .ctx = self,
            .draw = draw,
            .load = load,
            .unload = unload,
        };
    }

    fn draw(ctx: *anyopaque, render_ctx: RenderContext, y: f64, query: []const u8) void {
        _ = query;
        const self: *WeatherWidget = @ptrCast(@alignCast(ctx));

        self.extract_weather();

        const cr = render_ctx.cr;
        const icon_size: f64 = 28.0;
        const icon_x: f64 = 16.0;
        const icon_y: f64 = y + (constants.WIDGET_HEIGHT - icon_size) / 2.0;

        const weather_code = if (self.weather) |weather| weather.current.weather_code else 0;
        const weather_icon = render_ctx.icon_mod.loadEmbeddedIcon(Weather.iconFromWeatherCode(weather_code), colors.fg, icon_size);
        if (weather_icon) |icon| {
            c.cairo_set_source_surface(cr, icon, icon_x, icon_y);
            c.cairo_paint(cr);
        }

        const text_x = icon_x + icon_size + 4.0;
        var temp_buf: [16]u8 = undefined;
        const temp_txt = if (self.weather) |weather| std.fmt.bufPrint(&temp_buf, "{d} {s}", .{ weather.current.temperature, weather.units.temperature }) catch "--" else "--";
        const text_size = draw_text.measureText(cr, temp_txt, render_ctx.font_desc_small_str);
        const text_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(text_size.h))) / 2.0;
        const text_width = draw_text.drawTextMeasured(cr, temp_txt, render_ctx.font_desc_small_str, colors.fg, text_x, text_y).w;

        const wind_size = 22.0;
        const wind_y: f64 = y + (constants.WIDGET_HEIGHT - wind_size) / 2.0;
        const wind_x = text_x + @as(f64, @floatFromInt(text_width)) + 16.0;
        const wind_icon = render_ctx.icon_mod.loadEmbeddedIcon(Icons.WeatherWind, colors.placeholder, wind_size);
        if (wind_icon) |icon| {
            c.cairo_set_source_surface(cr, icon, wind_x, wind_y);
            c.cairo_paint(cr);
        }

        const w_text_x = wind_x + wind_size + 4.0;
        var wind_buf: [16]u8 = undefined;
        const wind_txt = if (self.weather) |weather| std.fmt.bufPrint(&wind_buf, "{d} {s}", .{ weather.current.temperature, weather.units.temperature }) catch "--" else "--";
        const wind_txt_size = draw_text.measureText(cr, wind_txt, render_ctx.font_desc_small_str);
        const wind_txt_y = y + (constants.WIDGET_HEIGHT - @as(f64, @floatFromInt(wind_txt_size.h))) / 2.0;
        draw_text.drawText(cr, wind_txt, render_ctx.font_desc_small_str, colors.placeholder, w_text_x, wind_txt_y);
    }

    fn extract_weather(self: *WeatherWidget) void {
        if (self.weather_req) |req| {
            const loc_res = self.net.try_value(req) catch |err| blk: {
                std.debug.print("Weather request failed before parsing: {}\n", .{err});
                self.net.release(req);
                self.weather_req = null;
                break :blk null;
            };
            if (loc_res) |res| {
                std.debug.print("Received weather response\n{s}\n", .{res});
                const e_weather = weather_extract.extract_weather(self.alloc, res) catch |err| blk: {
                    std.debug.print("Failed to extract weather from response: {}\n", .{err});
                    break :blk null;
                };
                if (e_weather) |weather| {
                    self.weather = Weather.initFromParsed(weather);
                    std.debug.print("Resolved user weather\n", .{});
                    self.weather.?.print();
                }
                self.net.release(req);
                self.weather_req = null;
            }
        }
    }

    fn load(ctx: *anyopaque) !void {
        const self: *WeatherWidget = @ptrCast(@alignCast(ctx));
        if (self.weather == null and self.weather_req == null) {
            std.debug.print("Wanting to fetch weather\n", .{});
            var w_req_buf: [128]u8 = undefined;
            const w_req_url: ?[]const u8 = blk: {
                std.debug.print("Testing if location not null\n", .{});
                if (self.loc.lat != null and self.loc.lon != null) {
                    std.debug.print("Formatting api url call\n", .{});
                    break :blk std.fmt.bufPrint(&w_req_buf, "https://api.open-meteo.com/v1/forecast?latitude={d}&longitude={d}&current_weather=true", .{ self.loc.lat.?, self.loc.lon.? }) catch null;
                }
                break :blk null;
            };
            if (w_req_url) |url| {
                std.debug.print("Fetching weather data\n", .{});
                self.weather_req = self.net.fetch(url) catch null;
            }
        }
    }

    fn unload(ctx: *anyopaque) !void {
        const self: *WeatherWidget = @ptrCast(@alignCast(ctx));
        if (self.weather_req) |req| {
            self.net.release(req);
        }
    }
};
