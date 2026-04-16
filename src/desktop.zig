const std = @import("std");
const constants = @import("constants.zig");
const Icon = @import("icons/icon_struct.zig").Icon;

pub const DesktopEntry = struct {
    name: []const u8,
    exec: []const u8,
    icon: Icon,
    comment: []const u8,
    path: []const u8,
    main_category: []const u8,
    sub_categories: []const []const u8,
    no_display: bool,
    hidden: bool,

    /// Get executable with field codes stripped.
    pub fn getCommand(self: *const DesktopEntry, buf: []u8) ?[]const u8 {
        var i: usize = 0;
        var out: usize = 0;
        const exec = self.exec;

        while (i < exec.len) {
            if (exec[i] == '%' and i + 1 < exec.len) {
                i += 2;
                if (i < exec.len and exec[i] == ' ') i += 1;
                continue;
            }
            if (out >= buf.len) return null;
            buf[out] = exec[i];
            out += 1;
            i += 1;
        }

        while (out > 0 and buf[out - 1] == ' ') out -= 1;

        if (out == 0) return null;
        return buf[0..out];
    }
};

pub const DesktopScanner = struct {
    entries: std.ArrayList(DesktopEntry),
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) DesktopScanner {
        return .{
            .entries = .empty,
            .arena = std.heap.ArenaAllocator.init(backing_allocator),
        };
    }

    pub fn deinit(self: *DesktopScanner) void {
        self.arena.deinit();
    }

    pub fn scan(self: *DesktopScanner) !void {
        const alloc = self.arena.allocator();
        var dirs: std.ArrayList([]const u8) = .empty;

        // $XDG_DATA_HOME/applications (default: ~/.local/share/applications)
        if (std.posix.getenv("XDG_DATA_HOME")) |data_home| {
            const path = try std.fmt.allocPrint(alloc, "{s}/applications", .{data_home});
            try dirs.append(alloc, path);
        } else if (std.posix.getenv("HOME")) |home| {
            const path = try std.fmt.allocPrint(alloc, "{s}/.local/share/applications", .{home});
            try dirs.append(alloc, path);
        }

        // $XDG_DATA_DIRS/applications (default: /usr/local/share:/usr/share)
        const data_dirs = std.posix.getenv("XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";
        var iter = std.mem.splitScalar(u8, data_dirs, ':');
        while (iter.next()) |dir| {
            if (dir.len == 0) continue;
            const path = try std.fmt.allocPrint(alloc, "{s}/applications", .{dir});
            try dirs.append(alloc, path);
        }

        // Flatpak paths
        if (std.posix.getenv("HOME")) |home| {
            try dirs.append(alloc, try std.fmt.allocPrint(alloc, "{s}/.local/share/flatpak/exports/share/applications", .{home}));
        }
        try dirs.append(alloc, try alloc.dupe(u8, "/var/lib/flatpak/exports/share/applications"));

        // Snap paths
        try dirs.append(alloc, try alloc.dupe(u8, "/var/lib/snapd/desktop/applications"));

        for (dirs.items) |dir_path| {
            self.scanDir(dir_path) catch continue;
        }

        std.mem.sort(DesktopEntry, self.entries.items, {}, struct {
            fn lessThan(_: void, a: DesktopEntry, b: DesktopEntry) bool {
                return std.ascii.lessThanIgnoreCase(a.name, b.name);
            }
        }.lessThan);
    }

    fn scanDir(self: *DesktopScanner, dir_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.arena.allocator());
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file and entry.kind != .sym_link) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".desktop")) continue;

            const full_path = try std.fmt.allocPrint(self.arena.allocator(), "{s}/{s}", .{ dir_path, entry.path });

            if (self.parseDesktopFile(dir, entry.path, full_path)) |desktop_entry| {
                if (desktop_entry.hidden or desktop_entry.no_display) continue;
                if (desktop_entry.name.len == 0 or desktop_entry.exec.len == 0) continue;

                const dominated = for (self.entries.items) |existing| {
                    if (std.mem.eql(u8, existing.name, desktop_entry.name)) break true;
                } else false;

                if (!dominated) {
                    try self.entries.append(self.arena.allocator(), desktop_entry);
                }
            }
        }
    }

    fn parseDesktopFile(self: *DesktopScanner, dir: std.fs.Dir, rel_path: []const u8, full_path: []const u8) ?DesktopEntry {
        const alloc = self.arena.allocator();

        const file = dir.openFile(rel_path, .{}) catch return null;
        defer file.close();

        const content = file.readToEndAlloc(alloc, 1024 * 64) catch return null;

        var entry = DesktopEntry{
            .name = "",
            .exec = "",
            .icon = Icon.initEmbedded(constants.DEFAULT_APPLICATION_ICON),
            .comment = "",
            .path = full_path,
            .main_category = "",
            .sub_categories = &.{},
            .no_display = false,
            .hidden = false,
        };

        var in_desktop_entry = false;
        var line_iter = std.mem.splitScalar(u8, content, '\n');

        var icon_value: ?[]const u8 = null;
        var main_category: []const u8 = "";
        var sub_cats: std.ArrayList([]const u8) = .empty;

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, &.{ '\r', ' ', '\t' });

            if (line.len == 0 or line[0] == '#') continue;

            if (line[0] == '[') {
                const trimmed = std.mem.trim(u8, line, &.{ ' ', '\t' });
                in_desktop_entry = std.mem.eql(u8, trimmed, "[Desktop Entry]");
                continue;
            }

            if (!in_desktop_entry) continue;

            // Parse key=value
            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                const key = std.mem.trimEnd(u8, line[0..eq], &.{ ' ', '\t' });
                const value = std.mem.trimStart(u8, line[eq + 1 ..], &.{ ' ', '\t' });

                if (std.mem.eql(u8, key, "Name")) {
                    if (entry.name.len == 0)
                        entry.name = alloc.dupe(u8, value) catch return null;
                } else if (std.mem.eql(u8, key, "GenericName")) {
                    if (entry.comment.len == 0)
                        entry.comment = alloc.dupe(u8, value) catch return null;
                } else if (std.mem.eql(u8, key, "Exec")) {
                    entry.exec = alloc.dupe(u8, value) catch return null;
                } else if (std.mem.eql(u8, key, "Icon")) {
                    icon_value = alloc.dupe(u8, value) catch return null;
                } else if (std.mem.eql(u8, key, "Comment")) {
                    entry.comment = alloc.dupe(u8, value) catch return null;
                } else if (std.mem.eql(u8, key, "Categories")) {
                    var cat_iter = std.mem.tokenizeScalar(u8, value, ';');
                    while (cat_iter.next()) |cat| {
                        if (main_category.len == 0 and constants.MAIN_CATEGORIES.get(cat) != null) {
                            main_category = alloc.dupe(u8, cat) catch cat;
                        } else {
                            sub_cats.append(alloc, alloc.dupe(u8, cat) catch continue) catch {};
                        }
                    }
                } else if (std.mem.eql(u8, key, "NoDisplay")) {
                    entry.no_display = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "Hidden")) {
                    entry.hidden = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "Type")) {
                    if (!std.mem.eql(u8, value, "Application")) return null;
                }
            }
        }

        entry.main_category = main_category;
        entry.sub_categories = sub_cats.items; // INFO: slight overallocation
        entry.icon = determineIcon(icon_value, main_category);

        return entry;
    }

    /// Classify the icon without touching the filesystem.
    fn determineIcon(name: ?[]const u8, main_cat: []const u8) Icon {
        const fallback = constants.MAIN_CATEGORIES.get(main_cat) orelse constants.DEFAULT_APPLICATION_ICON;
        if (name) |n| {
            if (n.len == 0) return Icon{ .embedded = fallback };
            // Absolute path: use it directly, no discovery needed.
            if (n[0] == '/') return Icon{ .path = n };
            // Named icon: defer filesystem discovery to render time.
            return Icon{ .name = .{ .icon_name = n, .fallback = fallback } };
        }
        // No Icon= field at all: use the category/default embedded icon.
        return Icon{ .embedded = fallback };
    }
};
