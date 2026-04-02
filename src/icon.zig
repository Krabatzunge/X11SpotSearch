const std = @import("std");
const assets = @import("assets.zig");
const c = @import("c.zig").c;

pub const IconType = enum { Icon, Path };

pub const IconCache = struct {
    map: std.StringHashMap(*c.cairo_surface_t),
    arena: std.heap.ArenaAllocator,
    icon_size: u16,

    search_dirs: []const []const u8,

    pub fn init(allocator: std.mem.Allocator, icon_size: u16) !IconCache {
        var arena = std.heap.ArenaAllocator.init(allocator);
        const alloc = arena.allocator();

        var dirs: std.ArrayList([]const u8) = .empty;

        const home = std.posix.getenv("HOME") orelse "/root";
        const data_dirs = std.posix.getenv("XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";

        const themes = [_][]const u8{
            "Adwaita", "breeze", "Papirus", "Papirus-Dark", "gnome", "elementary", "Humanity", "hicolor",
        };

        const categories = [_][]const u8{ "apps", "applications", "categories", "places", "devices", "actions" };

        const sizes = [_][]const u8{ "48x48", "32x32", "64x64", "128x128", "256x256", "96x96", "72x72", "36x36", "24x24", "512x512", "scalable" };

        // For each base dir -> theme -> size -> category
        var base_iter = std.mem.splitScalar(u8, data_dirs, ':');
        while (base_iter.next()) |base| {
            if (base.len == 0) continue;
            for (themes) |theme| {
                for (sizes) |size| {
                    for (categories) |cat| {
                        try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/icons/{s}/{s}/{s}", .{ base, theme, size, cat }));
                    }
                }
            }
        }

        // ~/.local/share/icons and ~/.icons
        for (themes) |theme| {
            for (sizes) |size| {
                for (categories) |cat| {
                    try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/.local/share/icons/{s}/{s}/{s}", .{ home, theme, size, cat }));
                    try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/.icons/{s}/{s}/{s}", .{ home, theme, size, cat }));
                }
            }
        }

        // Flatpak icons
        try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/.local/share/flatpak/exports/share/icons/hicolor/128x128/apps", .{home}));
        try dirs.append(alloc, try alloc.dupe(u8, "/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps"));
        try dirs.append(alloc, try alloc.dupe(u8, "/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps"));

        // Custom icon paths (JetBrains)
        try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/.local/share/JetBrains/Toolbox/apps", .{home}));

        // Pixmaps
        try dirs.append(alloc, try alloc.dupe(u8, "/usr/share/pixmaps"));
        try dirs.append(alloc, try alloc.dupe(u8, "/usr/local/share/pixmaps"));

        return .{
            .map = std.StringHashMap(*c.cairo_surface_t).init(allocator),
            .arena = arena,
            .icon_size = icon_size,
            .search_dirs = try dirs.toOwnedSlice(alloc),
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

    pub fn get(self: *IconCache, icon_name: []const u8, icon_type: IconType) ?*c.cairo_surface_t {
        if (icon_name.len == 0) return null;

        if (self.map.get(icon_name)) |surface| return surface;

        switch (icon_type) {
            IconType.Icon => return self.getIconFromData(icon_name),
            IconType.Path => return self.getIconFromPath(icon_name),
        }
    }

    pub fn getIconFromData(self: *IconCache, icon_id: []const u8) ?*c.cairo_surface_t {
        const icon = assets.Icons.fromId(icon_id) orelse return null;
        const surface = self.loadSvgFromMem(assets.Icons.getData(icon)) catch return null;
        if (surface) |sur| {
            self.map.put(icon_id, sur) catch {};
            return surface;
        }
        return null;
    }

    pub fn getIconFromPath(self: *IconCache, icon_name: []const u8) ?*c.cairo_surface_t {
        if (icon_name[0] == '/') {
            std.debug.print("Searching abosulte icon: {s}\n", .{icon_name});
            if (self.loadIcon(icon_name)) |surface| {
                std.debug.print("Loaded absolute icon: {s}\n", .{icon_name});
                self.map.put(icon_name, surface) catch {};
                return surface;
            }
            std.debug.print("Failed to load absolute icon: {s}\n", .{icon_name});
            return null;
        }

        const extensions = [_][]const u8{ ".png", ".svg", ".xpm" };
        const alloc = self.arena.allocator();

        for (self.search_dirs) |dir| {
            for (extensions) |ext| {
                const path = std.fmt.allocPrintSentinel(alloc, "{s}/{s}{s}", .{ dir, icon_name, ext }, 0) catch continue;

                if (self.loadIcon(path)) |surface| {
                    self.map.put(icon_name, surface) catch {};
                    return surface;
                }
            }
        }

        // some .desktop files may have an extension
        if (std.mem.indexOfScalar(u8, icon_name, '.') != null) {
            for (self.search_dirs) |dir| {
                const path = std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ dir, icon_name }, 0) catch continue;

                if (self.loadIcon(path)) |surface| {
                    self.map.put(icon_name, surface) catch {};
                    return surface;
                }
            }
        }

        return null;
    }

    fn loadIcon(self: *IconCache, path: []const u8) ?*c.cairo_surface_t {
        std.fs.cwd().access(path, .{}) catch return null;

        const alloc = self.arena.allocator();
        const path_z = alloc.dupeZ(u8, path) catch return null;

        if (std.mem.endsWith(u8, path, ".svg")) {
            return self.loadSvgFromPath(path_z.ptr);
        } else if (std.mem.endsWith(u8, path, ".png")) {
            std.debug.print("Loading png with page: {s}\n", .{path});
            return self.loadPngFromPath(path_z.ptr);
        }

        return null;
    }

    fn loadPngFromPath(self: *IconCache, path: [*c]const u8) ?*c.cairo_surface_t {
        const img = c.cairo_image_surface_create_from_png(path);
        std.debug.print("Creating cairo_surface for path\n", .{});
        if (c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(img);
            std.debug.print("Failed to create cairo_surface for path\n", .{});
            return null;
        }

        const img_w = c.cairo_image_surface_get_width(img);
        const img_h = c.cairo_image_surface_get_height(img);
        const target: f64 = @floatFromInt(self.icon_size);

        if (img_w == self.icon_size and img_h == self.icon_size) {
            return img;
        }

        const scaled = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(self.icon_size), @intCast(self.icon_size));
        const cr = c.cairo_create(scaled);
        defer c.cairo_destroy(cr);

        const sx = target / @as(f64, @floatFromInt(img_w));
        const sy = target / @as(f64, @floatFromInt(img_h));
        c.cairo_scale(cr, sx, sy);
        c.cairo_set_source_surface(cr, img, 0, 0);
        c.cairo_pattern_set_filter(c.cairo_get_source(cr), c.CAIRO_FILTER_BILINEAR);
        c.cairo_paint(cr);

        c.cairo_surface_destroy(img);
        return scaled;
    }

    fn loadSvgFromPath(self: *IconCache, path: [*c]const u8) ?*c.cairo_surface_t {
        const handle = c.rsvg_handle_new_from_file(path, null) orelse return null;
        defer c.g_object_unref(handle);

        const target: f64 = @floatFromInt(self.icon_size);

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(self.icon_size), @intCast(self.icon_size));
        const cr = c.cairo_create(surface);
        defer c.cairo_destroy(cr);

        var viewport = c.RsvgRectangle{
            .x = 0,
            .y = 0,
            .width = target,
            .height = target,
        };

        _ = c.rsvg_handle_render_document(handle, cr, &viewport, null);

        return surface;
    }

    fn loadSvgFromMem(self: *IconCache, data: []const u8) !?*c.cairo_surface_t {
        const handle = c.rsvg_handle_new_from_data(data.ptr, data.len, null) orelse return error.RsvgFailed;
        defer c.g_object_unref(handle);

        const target: f64 = @floatFromInt(self.icon_size);

        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(self.icon_size), @intCast(self.icon_size));
        const cr = c.cairo_create(surface);
        defer c.cairo_destroy(cr);

        var viewport = c.RsvgRectangle{ .x = 0, .y = 0, .width = target, .height = target };

        _ = c.rsvg_handle_render_document(handle, cr, &viewport, null);

        return surface;
    }
};
