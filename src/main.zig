const std = @import("std");
const c = @import("c.zig").c;
const Xkb = @import("xkb.zig").Xkb;
const Renderer = @import("renderer.zig").Renderer;
const constants = @import("constants.zig");
const Result = @import("result.zig").Result;
const desktop = @import("desktop.zig");
const fuzzy_match = @import("fuzzy.zig");

pub fn main() !void {
    var screen_num: c_int = 0;
    const conn = c.xcb_connect(null, &screen_num) orelse
        return error.XcbConnectionFailed;
    defer c.xcb_disconnect(conn);

    if (c.xcb_connection_has_error(conn) != 0)
        return error.XcbConnectionHasError;

    const setup = c.xcb_get_setup(conn);
    var iter = c.xcb_setup_roots_iterator(setup);

    var i: c_int = 0;
    while (i < screen_num) : (i += 1) {
        c.xcb_screen_next(&iter);
    }
    const screen = iter.data;

    const x: i16 = @intCast(@divTrunc(@as(i32, screen.*.width_in_pixels) - constants.WIN_WIDTH, 2));
    const y: i16 = @intCast(@divTrunc(@as(i32, screen.*.height_in_pixels) - @as(i32, @intFromFloat(constants.SEARCH_BAR_HEIGHT)), 3));

    const win = c.xcb_generate_id(conn);

    const value_mask = c.XCB_CW_BACK_PIXEL | c.XCB_CW_OVERRIDE_REDIRECT | c.XCB_CW_EVENT_MASK;
    const value_list = [_]u32{
        // XCB_CW_BACK_PIXEL
        0x1e1e2e,
        // XCB_CW_OVERRIDE_REDIRECT
        1,
        // XCB_CW_EVENT_MASK
        c.XCB_EVENT_MASK_EXPOSURE |
            c.XCB_EVENT_MASK_KEY_PRESS |
            c.XCB_EVENT_MASK_VISIBILITY_CHANGE |
            c.XCB_EVENT_MASK_FOCUS_CHANGE,
    };

    _ = c.xcb_create_window(conn, c.XCB_COPY_FROM_PARENT, win, screen.*.root, x, y, constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT, 0, c.XCB_WINDOW_CLASS_INPUT_OUTPUT, screen.*.root_visual, value_mask, &value_list);

    setEwmhHints(conn, win, screen);
    setMotifHints(conn, win);
    setWmClass(conn, win);
    setCompositorHints(conn, win);

    _ = c.xcb_map_window(conn, win);
    _ = c.xcb_set_input_focus(conn, c.XCB_INPUT_FOCUS_POINTER_ROOT, win, c.XCB_CURRENT_TIME);
    _ = c.xcb_flush(conn);

    var xkb = try Xkb.init(conn);
    defer xkb.deinit();

    const visual = findVisual(screen) orelse return error.VisualNotFound;
    var renderer = try Renderer.init(conn, screen, win, visual, constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT);
    defer renderer.deinit();

    var search_buf: [256]u8 = undefined;
    var search_len: usize = 0;

    const dummy_results = [_]Result{
        .{ .name = "Firefox", .description = "Web Browser" },
        .{ .name = "Files", .description = "File Manager" },
        .{ .name = "Ghosty", .description = "Terminal Emulator" },
        .{ .name = "Evolution", .description = "Email Client" },
        .{ .name = "Discord", .description = "Messaging App" },
    };

    var results_buf: [constants.MAX_RESULTS]Result = undefined;
    var results_count: usize = 0;
    var selected: usize = 0;

    std.debug.print("Launcher window shown at ({}, {}), size {}x{}\n", .{ x, y, constants.WIN_WIDTH, constants.SEARCH_BAR_HEIGHT });

    renderer.draw(search_buf[0..search_len], results_buf[0..0]);

    while (true) {
        const event = c.xcb_wait_for_event(conn) orelse break;
        defer std.c.free(event);

        const event_type: u8 = @intCast(event.*.response_type & ~@as(u8, 0x80));

        switch (event_type) {
            c.XCB_EXPOSE => {
                std.debug.print("Expose event - ready for drawing\n", .{});
                renderer.draw(search_buf[0..search_len], results_buf[0..results_count]);
                _ = c.xcb_flush(conn);
            },
            c.XCB_KEY_PRESS => {
                const key_event: *c.xcb_key_press_event_t = @ptrCast(event);
                //std.debug.print("Key press: keycode={}.\n", .{key_event.detail});
                const result = xkb.processKeyEvent(key_event.detail);
                var search_changed = false;

                switch (result.keysym) {
                    c.XKB_KEY_Escape => {
                        std.debug.print("Escape pressed, exiting.\n", .{});
                        return;
                    },
                    c.XKB_KEY_Return, c.XKB_KEY_KP_Enter => {
                        std.debug.print("Enter pressed - launch/do: \"{s}\"\n", .{search_buf[0..search_len]});
                        if (results_count > 0) {
                            std.debug.print("Launch: \"{s}\"\n", .{results_buf[selected].name});
                        }
                        //TODO: do stuff
                    },
                    c.XKB_KEY_BackSpace => {
                        if (search_len > 0) {
                            search_len -= 1;
                            while (search_len > 0 and (search_buf[search_len] & 0xC0) == 0x80) {
                                search_len -= 1;
                            }
                            search_changed = true;
                            std.debug.print("Search: \"{s}\"\n", .{search_buf[0..search_len]});
                        }
                    },
                    c.XKB_KEY_Up => {
                        if (selected > 0) {
                            selected -= 1;
                        }
                        std.debug.print("Going up in searches, new selected: {}\n", .{selected});
                    },
                    c.XKB_KEY_Down => {
                        if (results_count > 0 and selected < results_count - 1) {
                            selected += 1;
                        }
                        std.debug.print("Going down in searches, new selected: {}\n", .{selected});
                    },
                    else => {
                        if (result.text) |txt| {
                            if (search_len + txt.len < search_buf.len) {
                                @memcpy(search_buf[search_len .. search_len + txt.len], txt);
                                search_len += txt.len;
                                search_changed = true;
                                std.debug.print("Search: \"{s}\"\n", .{search_buf[0..search_len]});
                            }
                        }
                    },
                }

                xkb.updateState(conn);

                if (search_changed) {
                    results_count = 0;
                    selected = 0;
                    if (search_len > 0) {
                        for (dummy_results) |dr| {
                            if (results_count >= constants.MAX_RESULTS) break;
                            const search_lower = if (search_buf[0] >= 'A' and search_buf[0] <= 'Z')
                                search_buf[0] + 32
                            else
                                search_buf[0];
                            const name_lower = if (dr.name[0] >= 'A' and dr.name[0] <= 'Z')
                                dr.name[0] + 32
                            else
                                dr.name[0];

                            if (search_lower == name_lower) {
                                results_buf[results_count] = dr;
                                results_count += 1;
                            }
                        }
                    }
                }

                for (results_buf[0..results_count], 0..) |*r, j| {
                    r.selected = (j == selected);
                }

                renderer.resizeWindow(conn, win, results_count);
                renderer.draw(search_buf[0..search_len], results_buf[0..results_count]);
                _ = c.xcb_flush(conn);
            },
            c.XCB_FOCUS_OUT => {
                std.debug.print("Focus lost, exiting.\n", .{});
                return;
            },
            else => {},
        }
    }
}

fn setEwmhHints(conn: *c.xcb_connection_t, win: u32, screen: *c.xcb_screen_t) void {
    var ewmh: c.xcb_ewmh_connection_t = undefined;
    const cookies = c.xcb_ewmh_init_atoms(conn, &ewmh);
    _ = c.xcb_ewmh_init_atoms_replies(&ewmh, cookies, null);
    defer c.xcb_ewmh_connection_wipe(&ewmh);

    _ = c.xcb_ewmh_set_wm_window_type(&ewmh, win, 1, &ewmh._NET_WM_WINDOW_TYPE_DOCK);

    const states = [_]c.xcb_atom_t{
        ewmh._NET_WM_STATE_ABOVE,
        ewmh._NET_WM_STATE_SKIP_TASKBAR,
        ewmh._NET_WM_STATE_SKIP_PAGER,
    };
    _ = c.xcb_ewmh_set_wm_state(&ewmh, win, states.len, @constCast(&states));

    _ = c.xcb_ewmh_set_wm_desktop(&ewmh, win, 0xFFFFFFFF);

    _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, screen.*.root, ewmh._NET_ACTIVE_WINDOW, c.XCB_ATOM_WINDOW, 32, 1, @ptrCast(&win));
}

fn setMotifHints(conn: *c.xcb_connection_t, win: u32) void {
    // _MOTIF_WM_HINTS structure: flags, functions, decorations, input_mode, status
    const MWM_HINTS_DECORATIONS: u32 = 2;
    const motif_hints = [5]u32{
        MWM_HINTS_DECORATIONS,
        0,
        0,
        0,
        0,
    };

    const atom_cookie = c.xcb_intern_atom(conn, 0, 16, "_MOTIF_WM_HINTS");
    const atom_reply = c.xcb_intern_atom_reply(conn, atom_cookie, null);
    if (atom_reply) |reply| {
        defer std.c.free(reply);

        _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, reply.*.atom, reply.*.atom, 32, 5, @ptrCast(&motif_hints));
    }
}

fn setWmClass(conn: *c.xcb_connection_t, win: u32) void {
    // WM_CLASS is "instance\0class\0"
    const wm_class = "launcher\x00Launcher\x00";
    _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, c.XCB_ATOM_WM_CLASS, c.XCB_ATOM_STRING, 8, wm_class.len, wm_class.ptr);
}

fn setCompositorHints(conn: *c.xcb_connection_t, win: u32) void {
    {
        const cookie = c.xcb_intern_atom(conn, 0, 14, "_COMPTON_SHADOW");
        const reply = c.xcb_intern_atom_reply(conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(r);
            const val: u32 = 0; //no shadow
            _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, r.*.atom, c.XCB_ATOM_CARDINAL, 32, 1, @ptrCast(&val));
        }
    }
    {
        const cookie = c.xcb_intern_atom(conn, 0, 27, "_NET_WM_BYPASS_COMPOSITOR");
        const reply = c.xcb_intern_atom_reply(conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(r);
            const val: u32 = 1; // bypass compositing
            _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, r.*.atom, c.XCB_ATOM_CARDINAL, 32, 1, @ptrCast(&val));
        }
    }
}

fn findVisual(screen: *c.xcb_screen_t) ?*c.xcb_visualtype_t {
    var depth_iter = c.xcb_screen_allowed_depths_iterator(screen);
    while (depth_iter.rem > 0) {
        var visual_iter = c.xcb_depth_visuals_iterator(depth_iter.data);
        while (visual_iter.rem > 0) {
            if (visual_iter.data.*.visual_id == screen.*.root_visual) {
                return visual_iter.data;
            }
            c.xcb_visualtype_next(&visual_iter);
        }
        c.xcb_depth_next(&depth_iter);
    }
    return null;
}
