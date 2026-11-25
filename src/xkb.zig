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

    pub fn getKeycodeForKeysym(self: *Xkb, target_keysym: c.xkb_keysym_t) ?u8 {
        const min_keycode = c.xkb_keymap_min_keycode(self.keymap);
        const max_keycode = c.xkb_keymap_max_keycode(self.keymap);

        var keycode: c.xkb_keycode_t = min_keycode;
        while (keycode <= max_keycode) : (keycode += 1) {
            const sym = c.xkb_state_key_get_one_sym(self.state, keycode);
            if (sym == target_keysym) {
                if (keycode > 255) continue; // X11 core keycodes are 8-bit
                return @intCast(keycode);
            }
        }
        return null;
    }

    pub const KeyResult = struct {
        keysym: c.xkb_keysym_t,
        text_len: usize = 0, // 0 if not printable
        buf: [32]u8 = undefined,

        /// UTF-8 text of the key, null if not printable
        pub fn text(self: *const KeyResult) ?[]const u8 {
            if (self.text_len == 0) return null;
            return self.buf[0..self.text_len];
        }
    };

    /// Translates a key event using the modifier and layout state carried by the event itself,
    /// so queued events are not affected by keys pressed or released after them.
    pub fn processKeyEvent(self: *Xkb, xcb_keycode: u8, core_state: u16) KeyResult {
        const xkb_keycode: u32 = @as(u32, xcb_keycode);
        var result = KeyResult{
            .keysym = c.XKB_KEY_NoSymbol,
        };

        const mods: u32 = core_state & 0xFF;
        const group: u32 = (core_state >> 13) & 0x3;
        _ = c.xkb_state_update_mask(self.state, mods, 0, 0, 0, 0, group);

        result.keysym = c.xkb_state_key_get_one_sym(self.state, xkb_keycode);

        const len = c.xkb_state_key_get_utf8(self.state, xkb_keycode, &result.buf, result.buf.len);

        if (len > 0 and len < result.buf.len) {
            const n: usize = @intCast(len);
            if (!(n == 1 and std.ascii.isControl(result.buf[0]))) {
                result.text_len = n;
            }
        }

        return result;
    }
};
