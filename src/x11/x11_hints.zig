const c = @import("../c.zig").c;
const std = @import("std");

pub fn setEwmhHints(conn: *c.xcb_connection_t, win: u32, screen: *c.xcb_screen_t) void {
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

pub fn setMotifHints(conn: *c.xcb_connection_t, win: u32) void {
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

pub fn setCompositorHints(conn: *c.xcb_connection_t, win: u32) void {
    {
        const cookie = c.xcb_intern_atom(conn, 0, 14, "_COMPTON_SHADOW");
        const reply = c.xcb_intern_atom_reply(conn, cookie, null);
        if (reply) |r| {
            defer std.c.free(r);
            const val: u32 = 0; //no shadow
            _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, r.*.atom, c.XCB_ATOM_CARDINAL, 32, 1, @ptrCast(&val));
        }
    }
    //{
    //    const cookie = c.xcb_intern_atom(conn, 0, 27, "_NET_WM_BYPASS_COMPOSITOR");
    //    const reply = c.xcb_intern_atom_reply(conn, cookie, null);
    //    if (reply) |r| {
    //        defer std.c.free(r);
    //        const val: u32 = 1; // bypass compositing
    //        _ = c.xcb_change_property(conn, c.XCB_PROP_MODE_REPLACE, win, r.*.atom, c.XCB_ATOM_CARDINAL, 32, 1, @ptrCast(&val));
    //    }
    //}
}
