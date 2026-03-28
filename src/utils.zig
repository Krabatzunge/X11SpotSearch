const constants = @import("constants.zig");

pub fn calcHeight(result_count: usize) u16 {
    const base: f64 = constants.SEARCH_BAR_HEIGHT;
    if (result_count == 0) return @intFromFloat(base);
    return @intFromFloat(base + @as(f64, @floatFromInt(result_count)) * constants.RESULT_ITEM_HEIGHT + 4.0);
}
