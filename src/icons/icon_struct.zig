const EmbeddedIcons = @import("../assets.zig").Icons;

pub const Icon = union(enum) {
    path: []const u8,
    embedded: EmbeddedIcons,
    name: struct {
        icon_name: []const u8,
        fallback: EmbeddedIcons,
    },

    pub fn initEmbedded(icon: EmbeddedIcons) Icon {
        return Icon{ .embedded = icon };
    }

    pub fn initPath(path: []const u8) Icon {
        return Icon{ .path = path };
    }
};
