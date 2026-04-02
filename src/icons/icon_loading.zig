const std = @import("std");
const c = @import("../c.zig").c;
const Color = @import("../colors.zig").Color;

pub fn loadIconFromPath(path: []const u8, icon_size: u16) !*c.cairo_surface_t {
    std.debug.print("Beginning to load desktop icon: {s}\n", .{path});
    std.fs.cwd().access(path, .{}) catch return error.ImagePathNoneExistent;

    var path_buf: [512]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.PathTooLong;

    if (std.mem.endsWith(u8, path, ".svg")) {
        std.debug.print("Loading svg with path: {s}\n", .{path});
        return loadSvgFromPath(path_z.ptr, icon_size);
    } else if (std.mem.endsWith(u8, path, ".png")) {
        std.debug.print("Loading png with path: {s}\n", .{path});
        return loadPngFromPath(path_z.ptr, icon_size);
    }

    return error.NoImageLoaded;
}

fn loadPngFromPath(path: [*c]const u8, icon_size: u16) !*c.cairo_surface_t {
    const img = c.cairo_image_surface_create_from_png(path);
    std.debug.print("Creating cairo_surface for path: {s}\n", .{path});
    if (c.cairo_surface_status(img) != c.CAIRO_STATUS_SUCCESS) {
        c.cairo_surface_destroy(img);
        std.debug.print("Failed to create cairo_surface for path\n", .{});
        return error.CairoSurfaceFailed;
    }

    const img_w = c.cairo_image_surface_get_width(img);
    const img_h = c.cairo_image_surface_get_height(img);
    const target: f64 = @floatFromInt(icon_size);

    if (img_w == icon_size and img_h == icon_size) {
        return img orelse error.CouldNotLoadPng;
    }

    const scaled = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(icon_size), @intCast(icon_size)) orelse return error.CairoSurfaceFailed;
    const cr = c.cairo_create(scaled);
    defer c.cairo_destroy(cr);

    const sx = target / @as(f64, @floatFromInt(img_w));
    const sy = target / @as(f64, @floatFromInt(img_h));
    c.cairo_scale(cr, sx, sy);
    c.cairo_set_source_surface(cr, img, 0, 0);
    c.cairo_pattern_set_filter(c.cairo_get_source(cr), c.CAIRO_FILTER_BILINEAR);
    c.cairo_paint(cr);

    c.cairo_surface_destroy(img);
    return scaled;
}

fn loadSvgFromPath(path: [*c]const u8, icon_size: u16) !*c.cairo_surface_t {
    const handle = c.rsvg_handle_new_from_file(path, null) orelse return error.RsvgFailed;
    defer c.g_object_unref(handle);

    const target: f64 = @floatFromInt(icon_size);

    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(icon_size), @intCast(icon_size)) orelse return error.CairoSurfaceFailed;
    const cr = c.cairo_create(surface);
    defer c.cairo_destroy(cr);

    var viewport = c.RsvgRectangle{
        .x = 0,
        .y = 0,
        .width = target,
        .height = target,
    };

    _ = c.rsvg_handle_render_document(handle, cr, &viewport, null);

    return surface;
}

pub fn loadSvgFromMem(data: []const u8, icon_size: u16, color: Color) !*c.cairo_surface_t {
    const handle = c.rsvg_handle_new_from_data(data.ptr, data.len, null) orelse return error.RsvgFailed;
    defer c.g_object_unref(handle);

    const target: f64 = @floatFromInt(icon_size);

    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @intCast(icon_size), @intCast(icon_size)) orelse return error.CairoSurfaceFailed;
    const cr = c.cairo_create(surface);
    defer c.cairo_destroy(cr);

    var viewport = c.RsvgRectangle{ .x = 0, .y = 0, .width = target, .height = target };

    var css_buf: [48]u8 = undefined;
    const r: u8 = @intFromFloat(color.r * 255.0);
    const g: u8 = @intFromFloat(color.g * 255.0);
    const b: u8 = @intFromFloat(color.b * 255.0);
    const css = std.fmt.bufPrint(&css_buf, "svg{{color:#{x:0>2}{x:0>2}{x:0>2}}}", .{ r, g, b }) catch unreachable;
    _ = c.rsvg_handle_set_stylesheet(handle, css.ptr, css.len, null);

    _ = c.rsvg_handle_render_document(handle, cr, &viewport, null);

    return surface;
}
