const std = @import("std");
const c = @import("c.zig").c;

const lock_masks = [_]u16{ 0, 0x02, 0x10, 0x02 | 0x10 }; //none, caps, num, caps+num

fn grabHotKey(conn: *c.xcb_connection_t, root: u32, modifiers: u16, keycode: u8) void {
    for (lock_masks) |lock| {
        _ = c.xcb_grab_key(conn, 1, root, modifiers | lock, keycode, c.XCB_GRAB_MODE_ASYNC, c.XCB_GRAB_MODE_ASYNC);
        _ = c.xcb_flush(conn);
    }
}

fn ungrabHotkey(conn: *c.xcb_connection_t, root: u32, modifiers: u16, keycode: u8) void {
    for (lock_masks) |lock| {
        _ = c.xcb_ungrab_key(conn, keycode, root, modifiers | lock);
    }
    _ = c.xcb_flush(conn);
}

pub fn runDeamon(conn: *c.xcb_connection_t, root: u32, modifiers: u16, keycode: u8, spawnLauncher: *const fn () void) !void {
    grabHotKey(conn, root, modifiers, keycode);
    defer ungrabHotkey(conn, root, modifiers, keycode);

    std.debug.print("Deamon running. Listening for hotkey (mod=0x{x}, keycode={})...\n", .{ modifiers, keycode });

    // Use poll() for clean signal handling later if needed
    const xcb_fd = c.xcb_get_file_descriptor(conn);
    var fds = [_]c.struct_pollfd{
        .{ .fd = xcb_fd, .events = c.POLLIN, .revents = 0 },
    };

    while (true) {
        const ret = c.poll(&fds, 1, -1);
        if (ret < 0) break; // signal or error

        // Drain all events
        while (true) {
            const event = c.xcb_poll_for_event(conn) orelse break;
            defer std.c.free(event);

            const event_type: u8 = @intCast(event.*.response_type & ~@as(u8, 0x80));

            if (event_type == c.XCB_KEY_PRESS) {
                const key_event: *c.xcb_key_press_event_t = @ptrCast(event);

                // Strip lock key modifiers for comparison
                const clean_mod = key_event.state & ~@as(u16, 0x02 | 0x10);

                if (key_event.detail == keycode and clean_mod == modifiers) {
                    std.debug.print("Hotkey triggered!\n", .{});
                    spawnLauncher();
                }
            }
        }

        if (c.xcb_connection_has_error(conn) != 0) break;
    }
}
