const std = @import("std");
const c = @import("c.zig").c;
const build_options = @import("build_options");
const X11Platform = @import("x11/x11_platform.zig").X11Platform;
const WaylandPlatform = @import("wayland/wl_platform.zig").WaylandPlatform;
const utils = @import("utils.zig");

pub const KeyEvent = struct {
    keysym: u32,
    text: ?[]const u8,
};

pub const Platform = union(enum) {
    x11: X11Platform,
    wayland: WaylandPlatform,

    pub fn deinit(self: *Platform) void {
        switch (self.*) {
            .x11 => |*p| p.deinit(),
            .wayland => |*p| p.deinit(),
        }
    }

    pub fn getFd(self: *Platform) c_int {
        return switch (self.*) {
            .x11 => |*p| c.xcb_get_file_descriptor(p.conn.?),
            .wayland => |*p| c.wl_display_get_fd(p.display),
        };
    }

    pub fn prePoll(self: *Platform) void {
        switch (self.*) {
            .x11 => {},
            .wayland => |*p| _ = c.wl_display_flush(p.display),
        }
    }

    pub fn shouldClose(self: *Platform) bool {
        return switch (self.*) {
            .x11 => false, 
            .wayland => |*p| p.should_close,
        };
    }

    pub fn dispatchEvents(self: *Platform) DispatchResult {
        switch (self.*) {
            .x11 => |*p| return p.dispatchEvents(),
            .wayland => |*p| return p.dispatchEvents(),
        }
    }

    pub fn resize(self: *Platform, result_count: usize, has_widget: bool) void {
        switch (self.*) {
            .x11 => |*p| p.resize(result_count, has_widget),
            .wayland => |*p| {
                const new_height = utils.calcHeight(result_count, has_widget);
                p.resize(new_height);
            },
        }
    }

    pub fn beginFrame(self: *Platform) ?*c.cairo_t {
        switch (self.*) {
            .x11 => |*p| return p.cr,
            .wayland => |*p| {
                p.ensureBuffer() catch return null;
                return if (p.buffer) |buf| buf.cairo_cr else null;
            },
        }
    }

    pub fn commitFrame(self: *Platform) void {
        switch (self.*) {
            .x11 => |*p| _ = c.xcb_flush(p.conn.?),
            .wayland => |*p| p.commitFrame(),
        }
    }
};

pub const DispatchResult = union(enum) {
    none,
    close,
    key: KeyEvent,
    expose,
};
