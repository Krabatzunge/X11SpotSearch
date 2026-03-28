const std = @import("std");
const c = @import("c.zig").c;

pub const Xkb = struct {
    ctx: *c.xkb_context,
    keymap: *c.xkb_keymap,
    state: *c.xkb_state,

    pub fn init(conn: *c.xcb_connection_t) !Xkb {
        {
            const reply = c.xcb_xkb_use_extension_reply(conn, c.xcb_xkb_use_extension(conn, 1, 0), null);
            if (reply) |r| {
                defer std.c.free(r);
                if (r.*.supported == 0)
                    return error.XkbNotSupported;
            } else {
                return error.XkbExtensionFailed;
            }
        }

        const ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS) orelse
            return error.XkbContextFailed;
        errdefer c.xkb_context_unref(ctx);

        const device_id = c.xkb_x11_get_core_keyboard_device_id(conn);
        if (device_id == -1)
            return error.XkbDeviceFailed;

        const keymap = c.xkb_x11_keymap_new_from_device(
            ctx,
            conn,
            device_id,
            c.XKB_KEYMAP_COMPILE_NO_FLAGS,
        ) orelse return error.XkbKeymapFailed;
        errdefer c.xkb_keymap_unref(keymap);

        const state = c.xkb_x11_state_new_from_device(keymap, conn, device_id) orelse return error.XkbStateFailed;

        return .{ .ctx = ctx, .keymap = keymap, .state = state };
    }

    pub fn deinit(self: *Xkb) void {
        c.xkb_state_unref(self.state);
        c.xkb_keymap_unref(self.keymap);
        c.xkb_context_unref(self.ctx);
    }

    pub const KeyResult = struct {
        keysym: c.xkb_keysym_t,
        text: ?[]const u8, // UTF-8 slice, null if not printable
        buf: [32]u8 = undefined,
    };

    pub fn processKeyEvent(self: *Xkb, xcb_keycode: u8) KeyResult {
        const xkb_keycode: u32 = @as(u32, xcb_keycode);
        var result = KeyResult{
            .keysym = c.XKB_KEY_NoSymbol,
            .text = null,
        };

        result.keysym = c.xkb_state_key_get_one_sym(self.state, xkb_keycode);

        const len = c.xkb_state_key_get_utf8(self.state, xkb_keycode, &result.buf, result.buf.len);

        if (len > 0 and len < result.buf.len) {
            result.text = result.buf[0..@intCast(len)];
        }

        return result;
    }

    pub fn updateState(self: *Xkb, conn: *c.xcb_connection_t) void {
        const device_id = c.xkb_x11_get_core_keyboard_device_id(conn);
        if (device_id == -1) return;

        const new_state = c.xkb_x11_state_new_from_device(self.keymap, conn, device_id);
        if (new_state) |s| {
            c.xkb_state_unref(self.state);
            self.state = s;
        }
    }
};
