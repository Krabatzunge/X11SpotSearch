const Icon = @import("icons/icon_struct.zig").Icon;

pub const Result = struct {
    name: []const u8,
    description: []const u8,
    icon: Icon,
    selected: bool = false,
};
