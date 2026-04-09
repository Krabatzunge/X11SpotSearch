const std = @import("std");

pub const GeoResult = struct {
    latitude: f32,
    longitude: f32,
};

pub fn extract_geo_location(allocator: std.mem.Allocator, text: []const u8) !GeoResult {
    const tree = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return error.FailedToParseJson;
    defer tree.deinit();

    if (tree.value != .object) {
        return error.InvalidGeoResponse;
    }

    const results_value = tree.value.object.get("results") orelse {
        return error.MissingGeoResults;
    };

    if (results_value != .array) {
        return error.InvalidGeoResults;
    }

    const results_array = results_value.array;
    if (results_array.items.len == 0) {
        return error.EmptyGeoResults;
    }

    const first_result = results_array.items[0];
    if (first_result != .object) {
        return error.InvalidGeoResult;
    }

    if (!first_result.object.contains("latitude") or !first_result.object.contains("longitude")) {
        return error.MissingGeoCoordinates;
    }

    const parsed_result = std.json.parseFromValue(GeoResult, allocator, first_result, .{
        .ignore_unknown_fields = true,
    }) catch |err| return err;
    defer parsed_result.deinit();

    return parsed_result.value;
}
