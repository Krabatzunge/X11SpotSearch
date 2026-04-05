const constants = @import("constants.zig");

pub fn calcHeight(result_count: usize, has_widget: bool) u16 {
    const base: f64 = constants.SEARCH_BAR_HEIGHT;
    const results_h: f64 = if (result_count == 0) 0.0 else @as(f64, @floatFromInt(result_count)) * constants.RESULT_ITEM_HEIGHT + 4.0;
    const widget_h: f64 = if (has_widget) constants.WIDGET_HEIGHT + 1.0 else 0.0;
    if (result_count == 0 and !has_widget) return @intFromFloat(base);
    return @intFromFloat(base + results_h + widget_h);
}
