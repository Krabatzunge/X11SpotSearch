const std = @import("std");
const IconCache = @import("icon_cache.zig").IconCache;
const IconDiscover = @import("icon_discovery.zig").IconDiscovery;
const icon_loading = @import("icon_loading.zig");
const c = @import("../c.zig").c;
const EmbeddedIcons = @import("../assets.zig").Icons;
const Color = @import("../colors.zig").Color;

pub const IconModule = struct {
    icon_cache: IconCache,
    icon_discov: IconDiscover,

    pub fn init(allocator: std.mem.Allocator) !IconModule {
        return .{
            .icon_cache = try IconCache.init(allocator),
            .icon_discov = try IconDiscover.init(allocator),
        };
    }

    pub fn deinit(self: *IconModule) void {
        self.icon_cache.deinit();
        self.icon_discov.deinit();
    }

    pub fn loadDesktopIcon(self: *IconModule, name: []const u8, size: u16) ?*c.cairo_surface_t {
        var keybuf: [256]u8 = undefined;
        const key = IconCache.generateKeyFromPath(keybuf[0..256], name, size) catch return null;
        const cache_item = self.icon_cache.get(key);
        if (cache_item) |item| {
            return item;
        }
        const path = if (name[0] == '/') name else self.icon_discov.getIconFromPath(name) orelse return null;
        const surface = icon_loading.loadIconFromPath(path, size) catch return null;
        self.icon_cache.set(key, surface) catch {};
        return surface;
    }

    pub fn loadEmbeddedIcon(self: *IconModule, icon: EmbeddedIcons, color: Color, size: u16) ?*c.cairo_surface_t {
        var keybuf: [256]u8 = undefined;
        const key = IconCache.generateKeyFromEmbedded(keybuf[0..256], icon.toId(), size, color) catch return null;
        const cache_item = self.icon_cache.get(key);
        if (cache_item) |item| {
            return item;
        }
        const data = icon.getData();
        const surface = icon_loading.loadSvgFromMem(data, size, color) catch return null;
        self.icon_cache.set(key, surface) catch {};
        return surface;
    }
};
