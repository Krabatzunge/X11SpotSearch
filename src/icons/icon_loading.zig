const std = @import("std");
const c = @import("../c.zig").c;
const Color = @import("../colors.zig").Color;

pub fn loadIconFromPath(path: []const u8, icon_size: u16) !*c.cairo_surface_t {
    std.fs.cwd().access(path, .{}) catch return error.ImagePathNoneExistent;

    var path_buf: [512]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.PathTooLong;

    if (std.mem.endsWith(u8, path, ".svg")) {
        return loadSvgFromPath(path_z.ptr, icon_size);
    } else if (std.mem.endsWith(u8, path, ".png")) {
        return loadPngFromPath(path_z.ptr, icon_size);
    } else if (std.mem.endsWith(u8, path, ".xpm")) {
        return loadXpmFromPath(path_z.ptr, icon_size);
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

fn loadXpmFromPath(path: [*c]const u8, icon_size: u16) !*c.cairo_surface_t {
    const c_size: c_int = @intCast(icon_size);
    var err: ?*c.GError = null;
    const preserve_aspect_ratio: c_int = 0;
    const pixbuf = c.gdk_pixbuf_new_from_file_at_scale(path, c_size, c_size, preserve_aspect_ratio, &err) orelse return error.XpmLoadFailed;
    defer c.g_object_unref(pixbuf);

    const width = c.gdk_pixbuf_get_width(pixbuf);
    const height = c.gdk_pixbuf_get_height(pixbuf);
    const stride = c.gdk_pixbuf_get_rowstride(pixbuf);
    const pixels = c.gdk_pixbuf_get_pixels(pixbuf);
    const has_alpha = c.gdk_pixbuf_get_has_alpha(pixbuf) != 0;

    const fmt: c.cairo_format_t = if (has_alpha) c.CAIRO_FORMAT_ARGB32 else c.CAIRO_FORMAT_RGB24;

    const surface = c.cairo_image_surface_create(fmt, width, height) orelse return error.CairoSurfaceFailed;
    const cr = c.cairo_create(surface);
    defer c.cairo_destroy(cr);

    const cairo_stride = c.cairo_image_surface_get_stride(surface);
    const cairo_data = c.cairo_image_surface_get_data(surface);
    c.cairo_surface_flush(surface);

    var y: c_int = 0;
    while (y < height) : (y += 1) {
        var x: c_int = 0;
        while (x < width) : (x += 1) {
            const src = pixels + @as(usize, @intCast(y * stride + x * (if (has_alpha) @as(c_int, 4) else @as(c_int, 3))));
            const dst = cairo_data + @as(usize, @intCast(y * cairo_stride + x * 4));

            const r = src[0];
            const g = src[1];
            const b = src[2];
            const a: u8 = if (has_alpha) src[3] else 0xFF;

            dst[0] = @truncate(@as(u16, b) * a / 255);
            dst[1] = @truncate(@as(u16, g) * a / 255);
            dst[2] = @truncate(@as(u16, r) * a / 255);
            dst[3] = a;
        }
    }

    c.cairo_surface_mark_dirty(surface);
    return surface;
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
