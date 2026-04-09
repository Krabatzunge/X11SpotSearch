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
        var config = Config.default();

        var line_iter = std.mem.splitScalar(u8, content, '\n');

        while (line_iter.next()) |raw_line| {
            const line = std.mem.trimEnd(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') continue;

            if (line[0] == '[') {
                const trimmed = std.mem.trim(u8, line, &.{ ' ', '\t' });
                if (std.mem.eql(u8, trimmed, "[location]")) {
                    config.loc = self.parseLocationPart(&line_iter);
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
            const line = std.mem.trimEnd(u8, raw_line, &.{ '\r', ' ', '\t' });
            if (line.len == 0 or line[0] == '#') continue;

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

            if (line_iter.peek()) |peek_line| {
                const p_line = std.mem.trimEnd(u8, peek_line, &.{ '\r', ' ', '\t' });

                if (p_line.len > 0) {
                    if (p_line[0] == '[') {
                        break;
                    }
                }
            }
        }

        return loc_config;
    }
};
