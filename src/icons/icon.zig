const std = @import("std");
const IconCache = @import("icon_cache.zig").IconCache;
const IconDiscover = @import("icon_discovery.zig").IconDiscovery;
const icon_loading = @import("icon_loading.zig");
const c = @import("../c.zig").c;
const EmbeddedIcons = @import("../assets.zig").Icons;
const Color = @import("../colors.zig").Color;
const Icon = @import("icon_struct.zig").Icon;
const icon_loader = @import("icon_loader.zig");

const IconLoader = icon_loader.IconLoader;
const IconRequest = icon_loader.IconRequest;

pub const IconModule = struct {
    icon_cache: IconCache,
    icon_discov: IconDiscover,
    name_cache: std.StringHashMap(?[]const u8),
    name_arena: std.heap.ArenaAllocator,
    icon_loader: *IconLoader,

    pub fn init(allocator: std.mem.Allocator) !IconModule {
        return .{
            .icon_cache = try IconCache.init(allocator),
            .icon_discov = try IconDiscover.init(allocator),
            .name_cache = std.StringHashMap(?[]const u8).init(allocator),
            .name_arena = std.heap.ArenaAllocator.init(allocator),
            .icon_loader = undefined,
        };
    }

    pub fn startLoader(self: *IconModule, g_alloc: std.mem.Allocator, event_fd: std.posix.fd_t) !void {
        self.icon_loader = try IconLoader.init(g_alloc, &self.icon_cache, event_fd);
    }

    pub fn deinit(self: *IconModule) void {
        self.icon_cache.deinit();
        self.icon_discov.deinit();
        self.name_cache.deinit();
        self.name_arena.deinit();
        self.icon_loader.deinit();
    }

    pub fn loadIcon(self: *IconModule, icon: Icon, size: u16, color: Color) ?*c.cairo_surface_t {
        switch (icon) {
            .path => |p| return self.loadPathIcon(p, size),
            .embedded => |e| return self.loadEmbeddedIcon(e, color, size),
            .name => |n| return self.loadNameIcon(n.icon_name, n.fallback, size, color),
        }
    }

    fn loadNameIcon(self: *IconModule, icon_name: []const u8, fallback: EmbeddedIcons, size: u16, color: Color) ?*c.cairo_surface_t {
        if (self.name_cache.get(icon_name)) |maybe_path| {
            if (maybe_path) |path| {
                return self.loadPathIcon(path, size);
            } else {
                // Known miss — skip straight to the fallback.
                return self.loadEmbeddedIcon(fallback, color, size); 
            }
        }

        const resolved = self.icon_discov.getIconFromPath(icon_name);

        const owned_name = self.name_arena.allocator().dupe(u8, icon_name) catch {
            if (resolved) |p| return self.loadPathIcon(p, size);
            return self.loadEmbeddedIcon(fallback, color, size);
        };
        self.name_cache.put(owned_name, resolved) catch {};

        if (resolved) |p| {
            return self.loadPathIcon(p, size);
        } else {
            return self.loadEmbeddedIcon(fallback, color, size);
        }
    }

    pub fn loadPathIcon(self: *IconModule, path: []const u8, size: u16) ?*c.cairo_surface_t {
        var keybuf: [256]u8 = undefined;
        const key = IconCache.generateKeyFromPath(keybuf[0..256], path, size) catch return null;
        if (self.icon_loader.getCached(key)) |item| return item;
        self.icon_loader.request(IconRequest{
            .path = path,
            .size = size,
            .key = key,
        });      
        return null;
        //const surface = icon_loading.loadIconFromPath(path, size) catch return null;
        //self.icon_cache.set(key, surface) catch {};
        //return surface; //TODO: for icon thread loading return null and send request to thread
    }

    pub fn loadEmbeddedIcon(self: *IconModule, icon: EmbeddedIcons, color: Color, size: u16) ?*c.cairo_surface_t {
        var keybuf: [256]u8 = undefined;
        const key = IconCache.generateKeyFromEmbedded(keybuf[0..256], icon.toId(), size, color) catch return null;
        if (self.icon_cache.get(key)) |item| return item;
        const data = icon.getData();
        const surface = icon_loading.loadSvgFromMem(data, size, color) catch return null;
        self.icon_cache.set(key, surface) catch {};
        return surface;
    }
};
