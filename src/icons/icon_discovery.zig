const std = @import("std");

pub const IconDiscovery = struct {
    arena: std.heap.ArenaAllocator,
    search_dirs: []const []const u8,

    pub fn init(allocator: std.mem.Allocator) !IconDiscovery {
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
            .arena = arena,
            .search_dirs = try dirs.toOwnedSlice(alloc),
        };
    }

    pub fn deinit(self: *IconDiscovery) void {
        self.arena.deinit();
    }

    pub fn getIconFromPath(self: *IconDiscovery, icon_name: []const u8) ?[]const u8 {
        const extensions = [_][]const u8{ ".png", ".svg", ".xpm" };
        const alloc = self.arena.allocator();

        std.debug.print("Searching for icon: {s}\n", .{icon_name});

        for (self.search_dirs) |dir| {
            for (extensions) |ext| {
                const path = std.fmt.allocPrint(alloc, "{s}/{s}{s}", .{ dir, icon_name, ext }) catch continue;
                std.fs.cwd().access(path, .{}) catch continue;
                return path;
            }
        }

        // some .desktop files may have an extension
        if (std.mem.indexOfScalar(u8, icon_name, '.') != null) {
            for (self.search_dirs) |dir| {
                const path = std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir, icon_name }) catch continue;
                std.fs.cwd().access(path, .{}) catch continue;
                return path;
            }
        }

        return null;
    }
};
