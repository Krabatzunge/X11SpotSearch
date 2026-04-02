const std = @import("std");
const c = @import("../c.zig").c;
const Color = @import("../colors.zig").Color;

pub const IconCache = struct {
    map: std.StringHashMap(*c.cairo_surface_t),
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: std.mem.Allocator) !IconCache {
        const arena = std.heap.ArenaAllocator.init(allocator);

        return .{
            .map = std.StringHashMap(*c.cairo_surface_t).init(allocator),
            .arena = arena,
        };
    }

    pub fn deinit(self: *IconCache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            c.cairo_surface_destroy(entry.value_ptr.*);
        }
        self.map.deinit();
        self.arena.deinit();
    }

    pub fn get(self: *IconCache, key: []const u8) ?*c.cairo_surface_t {
        if (key.len == 0) return null;

        if (self.map.get(key)) |surface| return surface;

        return null;
    }

    pub fn set(self: *IconCache, key: []const u8, surface: *c.cairo_surface_t) !void {
        if (key.len == 0) return error.IdCanNotBeEmpty;

        if (self.map.contains(key)) return error.IdAlreadyExists;

        const owned = self.arena.allocator().dupe(u8, key) catch return error.CouldNotOwnKey;

        self.map.put(owned, surface) catch {};
    }

    pub fn generateKeyFromPath(buf: []u8, path: []const u8, size: u16) ![]const u8 {
        return std.fmt.bufPrint(buf, "p:{d}:{s}", .{ size, path });
    }

    pub fn generateKeyFromEmbedded(buf: []u8, id: []const u8, size: u16, color: Color) ![]const u8 {
        const r: u8 = @intFromFloat(color.r * 255.0);
        const g: u8 = @intFromFloat(color.g * 255.0);
        const b: u8 = @intFromFloat(color.b * 255.0);
        return std.fmt.bufPrint(buf, "e:{d}:{s}:{x:0>2}{x:0>2}{x:0>2}", .{ size, id, r, g, b });
    }
};
