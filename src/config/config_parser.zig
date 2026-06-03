const std = @import("std");
const config_mod = @import("config.zig");
const constants = @import("../constants.zig");

const Config = config_mod.Config;

pub const ConfigParser = struct {
    long_arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigParser {
        return .{
            .long_arena = std.heap.ArenaAllocator.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConfigParser) void {
        self.long_arena.deinit();
    }

    pub fn parseConfig(self: *ConfigParser) Config {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        const alloc = arena.allocator();
        defer arena.deinit();

        const config_path = self.getConfigPath(alloc) catch return Config.default();

        const file = std.fs.cwd().openFile(config_path, .{ .mode = .read_only }) catch return Config.default();
        defer file.close();

        const content = file.readToEndAlloc(alloc, 1024 * 64) catch return Config.default();
        return self.parseConfigContent(content);
    }

    fn parseConfigContent(self: *ConfigParser, content: []const u8) Config {
        var config = Config.default();
        var line_iter = std.mem.splitScalar(u8, content, '\n');

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') continue;

            if (line[0] == '[') {
                const trimmed = std.mem.trim(u8, line, &.{ ' ', '\t' });
                if (std.mem.eql(u8, trimmed, "[location]")) {
                    config.loc = self.parseLocationPart(&line_iter);
                } else if (std.mem.eql(u8, trimmed, "[search]")) {
                    config.search = self.parseSearchPart(&line_iter);
                }
                continue;
            }
        }

        return config;
    }

    fn getConfigPath(self: *ConfigParser, alloc: std.mem.Allocator) ![]const u8 {
        _ = self;
        const config_base = std.process.getEnvVarOwned(alloc, "XDG_CONFIG_HOME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => blk: {
                const home = try std.process.getEnvVarOwned(alloc, "HOME");
                break :blk try std.fs.path.join(alloc, &.{ home, ".config" });
            },
            else => return err,
        };

        return try std.fs.path.join(alloc, &.{ config_base, constants.APP_NAME, "config.toml" });
    }

    fn parseLocationPart(self: *ConfigParser, line_iter: *std.mem.SplitIterator(u8, .scalar)) config_mod.Location {
        const long_alloc = self.long_arena.allocator();
        var loc_config = config_mod.Location.default();

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') {
                if (nextSectionStarts(line_iter)) break;
                continue;
            }

            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                const key = std.mem.trimEnd(u8, line[0..eq], &.{ ' ', '\t' });
                const value = std.mem.trimStart(u8, line[eq + 1 ..], &.{ ' ', '\t' });
                const owned_value = long_alloc.dupe(u8, value) catch continue;

                if (std.mem.eql(u8, key, "lang")) {
                    loc_config.lang = std.mem.trim(u8, owned_value, &.{'"'});
                } else if (std.mem.eql(u8, key, "lon")) {
                    loc_config.lon = std.fmt.parseFloat(f32, owned_value) catch continue;
                } else if (std.mem.eql(u8, key, "lat")) {
                    loc_config.lat = std.fmt.parseFloat(f32, owned_value) catch continue;
                } else if (std.mem.eql(u8, key, "city")) {
                    loc_config.city = std.mem.trim(u8, owned_value, &.{'"'});
                }
            }

            if (nextSectionStarts(line_iter)) break;
        }

        return loc_config;
    }

    fn parseSearchPart(self: *ConfigParser, line_iter: *std.mem.SplitIterator(u8, .scalar)) config_mod.Search {
        const long_alloc = self.long_arena.allocator();
        var sear_config = config_mod.Search.default();

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') {
                if (nextSectionStarts(line_iter)) break;
                continue;
            }

            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                const key = std.mem.trimEnd(u8, line[0..eq], &.{ ' ', '\t' });
                const value = std.mem.trimStart(u8, line[eq + 1 ..], &.{ ' ', '\t' });
                const owned_value = long_alloc.dupe(u8, value) catch continue;

                if (std.mem.eql(u8, key, "engine-path")) {
                    sear_config.search_engine = std.mem.trim(u8, owned_value, &.{'"'});
                }
                if (std.mem.eql(u8, key, "engines")) {
                    const list_line = std.mem.trim(u8, value, &.{ '[', ']', ' ', '\t' });
                    var list_iter = std.mem.tokenizeSequence(u8, list_line, "},");
                    var engine_list: std.ArrayList(config_mod.SearchEngine) = .empty;
                    while (list_iter.next()) |raw_list_item| {
                        var engine = config_mod.SearchEngine.default();

                        const list_item = std.mem.trim(u8, raw_list_item, &.{ '{', '}', ' ', '\t', ',' });
                        var data_iter = std.mem.tokenizeScalar(u8, list_item, ',');

                        while (data_iter.next()) |raw_data| {
                            if (std.mem.indexOfScalar(u8, raw_data, '=')) |data_eq| {
                                const item_key = std.mem.trim(u8, raw_data[0..data_eq], &.{ ' ', '\t' });
                                const item_value = std.mem.trim(u8, raw_data[data_eq + 1 ..], &.{ ' ', '\t' });
                                if (std.mem.eql(u8, item_key, "name")) {
                                    const owned_item_value = long_alloc.dupe(u8, item_value) catch continue;
                                    engine.name = std.mem.trim(u8, owned_item_value, &.{ '"', ' ', '\t' });
                                } else if (std.mem.eql(u8, item_key, "path")) {
                                    const owned_item_value = long_alloc.dupe(u8, item_value) catch continue;
                                    engine.path = std.mem.trim(u8, owned_item_value, &.{ '"', ' ', '\t' });
                                }
                            }
                        }
                        if (engine.name.len == 0 or engine.path.len == 0) continue;
                        engine_list.append(long_alloc, engine) catch continue;
                    }
                    const owned_engines = engine_list.toOwnedSlice(long_alloc) catch continue;
                    sear_config.engines = owned_engines;
                }
            }

            if (nextSectionStarts(line_iter)) break;
        }

        return sear_config;
    }

    fn nextSectionStarts(line_iter: *std.mem.SplitIterator(u8, .scalar)) bool {
        var lookahead = line_iter.*;

        while (lookahead.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') continue;
            return line[0] == '[';
        }

        return false;
    }
};

test "parseConfigContent handles section transition after blank lines" {
    var parser = ConfigParser.init(std.testing.allocator);
    defer parser.deinit();
    var short_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer short_arena.deinit();

    const config = parser.parseConfigContent(
        \\[location]
        \\lang = "de"
        \\city = "Berlin"
        \\
        \\[search]
        \\engine-path = "https://search.magmaservices.de?q={s}"
        \\engines = [ { name = "github", path = "https://github.com/search?q={s}" } ]
        ,
        short_arena.allocator()
    );

    try std.testing.expectEqualStrings("de", config.loc.lang);
    try std.testing.expectEqualStrings("Berlin", config.loc.city.?);
    try std.testing.expectEqualStrings("https://search.magmaservices.de?q={s}", config.search.search_engine);
    try std.testing.expectEqual(@as(usize, 1), config.search.engines.len);
    try std.testing.expectEqualStrings("github", config.search.engines[0].name);
    try std.testing.expectEqualStrings("https://github.com/search?q={s}", config.search.engines[0].path);
}

test "parseConfigContent ignores incomplete search engines" {
    var parser = ConfigParser.init(std.testing.allocator);
    defer parser.deinit();
    var short_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer short_arena.deinit();

    const config = parser.parseConfigContent(
        \\[search]
        \\engines = [ { name = "github" }, { path = "https://duckduckgo.com/?q={s}" } ]
        ,
        short_arena.allocator()
    );

    try std.testing.expectEqual(@as(usize, 0), config.search.engines.len);
}
