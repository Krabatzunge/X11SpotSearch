const EmbeddedIcons = @import("../assets.zig").Icons;

pub const Icon = union(enum) {
    /// A resolved absolute filesystem path to a .png/.svg icon.
    path: []const u8,
    /// A compile-time-embedded fallback SVG (no filesystem lookup needed).
    embedded: EmbeddedIcons,
    /// An unresolved icon name from a .desktop file. Discovery is deferred to
    /// render time so that scanning desktop files stays fast.  If discovery
    /// fails the `fallback` embedded icon is used instead.
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
