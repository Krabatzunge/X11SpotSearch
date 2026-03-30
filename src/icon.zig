const std = @import("std");

const c = @import("c.zig").c;

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

        //const categories = [_][]const u8{ "apps", "applications", "categories", "places", "devices", "actions" };

        const size_str = try std.fmt.allocPrint(alloc, "{}", .{icon_size});
        const size_dir = try std.fmt.allocPrint(alloc, "{0}x{0}", .{icon_size});

        var dir_iter = std.mem.splitScalar(u8, data_dirs, ':');
        while (dir_iter.next()) |base| {
            if (base.len == 0) continue;
            for (themes) |theme| {
                try dirs.append(alloc, try std.fmt.allocPrint(
                    alloc,
                    "{s}/icons/{s}/{s}/apps",
                    .{ base, theme, size_dir },
                ));
                try dirs.append(alloc, try std.fmt.allocPrint(
                    alloc,
                    "{s}/icons/{s}/scalable/apps",
                    .{ base, theme },
                ));
            }
        }

        for (themes) |theme| {
            try dirs.append(alloc, try std.fmt.allocPrint(
                alloc,
                "{s}/.local/share/icons/{s}/{s}/apps",
                .{ home, theme, size_dir },
            ));
            try dirs.append(alloc, try std.fmt.allocPrint(
                alloc,
                "{s}/.icons/{s}/{s}/apps",
                .{ home, theme, size_dir },
            ));
        }

        try dirs.append(alloc, try alloc.dupe(u8, "/usr/share/pixmaps"));

        _ = size_str;

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

    pub fn get(self: *IconCache, icon_name: []const u8) ?*c.cairo_surface_t {
        if (icon_name.len == 0) return null;

        if (self.map.get(icon_name)) |surface| return surface;

        if (icon_name[0] == '/') {
            if (self.loadIcon(icon_name)) |surface| {
                self.map.put(icon_name, surface) catch {};
                return surface;
            }
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

        return null;
    }

    fn loadIcon(self: *IconCache, path: []const u8) ?*c.cairo_surface_t {
        std.fs.cwd().access(path, .{}) catch return null;

        const path_z: [*c]const u8 = @ptrCast(path.ptr);

        if (std.mem.endsWith(u8, path, ".svg")) {
            return self.loadSvg(path_z);
        } else if (std.mem.endsWith(u8, path, ".png")) {
            return self.loadPng(path_z);
        }

        return null;
    }

    fn loadPng(self: *IconCache, path: [*c]const u8) ?*c.cairo_surface_t {
        const img = c.cairo_image_surface_create_from_png(path);
        if (c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
            c.cairo_surface_destroy(img);
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
        c.cairo_paint(cr);

        c.cairo_surface_destroy(img);
        return scaled;
    }

    fn loadSvg(self: *IconCache, path: [*c]const u8) ?*c.cairo_surface_t {
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
};
