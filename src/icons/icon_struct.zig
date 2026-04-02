const Color = @import("../colors.zig").Color;
const EmbeddedIcons = @import("../assets.zig").Icons;

pub const Icon = union(enum) {
    path: []const u8,
    embedded: EmbeddedIcon,

    pub fn initEmbedded(icon: EmbeddedIcons, color: Color) Icon {
        return Icon{ .embedded = .{
            .icon = icon,
            .color = color,
        } };
    }

    pub fn initPath(path: []const u8) Icon {
        return Icon{ .path = path };
    }
};

pub const EmbeddedIcon = struct {
    icon: EmbeddedIcons,
    color: Color,
};
