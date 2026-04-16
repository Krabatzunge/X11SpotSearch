const std = @import("std");
const c = @import("../c.zig").c;

pub const ShmBuffer = struct {
    wl_buffer: *c.wl_buffer,
    data: [*]u8,
    size: usize,
    width: u32,
    heigh: u32,
    cairo_surface: *c.cairo_surface_t,
    cairo_cr: *c.cairo_t,

    pub fn create(shm: *c.wl_shm, width: u32, height: u32) !ShmBuffer {
        const stride = width * 4; // ARGB32
        const size = height * stride;

        const name = "spotsearch-shm";
        const fd = c.shm_open(name, c.O_RDWR | c.O_CREAT | c.O_EXCL, 0o600);

        if (fd < 0) return error.ShmOpenFailed;
        _ = c.shm_unlink(name);

        if (c.ftruncate(fd, @intCast(size)) < 0) {
            std.posix.close(fd);
            return error.FtruncateFailed;
        }

        const data = c.mmap(null, size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (data == c.MAP_FAILED) {
            std.posix.close(fd);
            return error.MmapFailed;
        }

        const pool = c.wl_shm_create_pool(shm, fd, @intCast(size));
        std.posix.close(fd);

        const wl_buffer = c.wl_shm_pool_create_buffer(pool, 0, @intCast(width), @intCast(height), @intCast(stride), c.WL_SHM_FORMAT_ARGB8888) orelse {
            c.wl_shm_pool_destroy(pool);
            return error.BufferCreateFailed;
        };
        c.wl_shm_pool_destroy(pool);

        const cairo_surface = c.cairo_image_surface_create_for_data(@ptrCast(data), c.CAIRO_FORMAT_ARGB32, @intCast(width), @intCast(height), @intCast(stride)) orelse return error.CairoSurfaceFailed;
        const cairo_cr = c.cairo_create(cairo_surface) orelse {
            c.cairo_surface_destroy(cairo_surface);
            return error.CairoCreateFailed;
        };

        return .{
            .wl_buffer = wl_buffer,
            .data = @ptrCast(data),
            .size = size,
            .width = width,
            .heigh = height,
            .cairo_surface = cairo_surface,
            .cairo_cr = cairo_cr,
        };
    }

    pub fn deinit(self: *ShmBuffer) void {
        c.cairo_destroy(self.cairo_cr);
        c.cairo_surface_destroy(self.cairo_surface);
        c.wl_buffer_destroy(self.wl_buffer);
        _ = c.munmap(self.data, self.size);
    }
};
