const std = @import("std");

pub const Icons = enum {
    Browser,
    DefaultApplication,
    DefCatDevelopment,
    DefCatEducation,
    DefCatGame,
    DefCatGraphics,
    DefCatMedia,
    DefCatNetwork,
    DefCatOffice,
    DefCatScience,
    DefCatSettings,
    DefCatSystem,
    DefCatUtility,

    const IconEntry = struct { tag: Icons, data: []const u8, id: []const u8 };

    const entries = [_]IconEntry{
        .{ .tag = .Browser, .data = @embedFile("./assets/icons/browser.svg"), .id = "icons.browser" },
        .{ .tag = .DefaultApplication, .data = @embedFile("./assets/icons/default-application.svg"), .id = "icons.default_application" },
        .{ .tag = .DefCatDevelopment, .data = @embedFile("./assets/icons/default-categories/development.svg"), .id = "icons.def.cat.development" },
        .{ .tag = .DefCatEducation, .data = @embedFile("./assets/icons/default-categories/education.svg"), .id = "icons.def.cat.education" },
        .{ .tag = .DefCatGame, .data = @embedFile("./assets/icons/default-categories/game.svg"), .id = "icons.def.cat.game" },
        .{ .tag = .DefCatGraphics, .data = @embedFile("./assets/icons/default-categories/graphics.svg"), .id = "icons.def.cat.graphics" },
        .{ .tag = .DefCatMedia, .data = @embedFile("./assets/icons/default-categories/media.svg"), .id = "icons.def.cat.media" },
        .{ .tag = .DefCatNetwork, .data = @embedFile("./assets/icons/default-categories/network.svg"), .id = "icons.def.cat.network" },
        .{ .tag = .DefCatOffice, .data = @embedFile("./assets/icons/default-categories/office.svg"), .id = "icons.def.cat.office" },
        .{ .tag = .DefCatScience, .data = @embedFile("./assets/icons/default-categories/science.svg"), .id = "icons.def.cat.science" },
        .{ .tag = .DefCatSettings, .data = @embedFile("./assets/icons/default-categories/settings.svg"), .id = "icons.def.cat.settings" },
        .{ .tag = .DefCatSystem, .data = @embedFile("./assets/icons/default-categories/system.svg"), .id = "icons.def.cat.system" },
        .{ .tag = .DefCatUtility, .data = @embedFile("./assets/icons/default-categories/utility.svg"), .id = "icons.def.cat.utility" },
    };

    // Compile-time safety: ensure every enum variant has exactly one table entry.
    comptime {
        if (@typeInfo(Icons).@"enum".fields.len != entries.len)
            @compileError("entries table is out of sync with Icons enum");
    }

    pub fn getData(icon: Icons) []const u8 {
        inline for (entries) |e| {
            if (icon == e.tag) return e.data;
        }
        unreachable;
    }

    pub fn toId(icon: Icons) []const u8 {
        inline for (entries) |e| {
            if (icon == e.tag) return e.id;
        }
        unreachable;
    }

    pub fn fromId(id: []const u8) ?Icons {
        for (entries) |e| {
            if (std.mem.eql(u8, id, e.id)) return e.tag;
        }
        return null;
    }
};
