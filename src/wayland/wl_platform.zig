const std = @import("std");
const c = @import("../c.zig").c;
const constants = @import("../constants.zig");
const ShmBuffer = @import("shm_buffer.zig").ShmBuffer;

pub const WaylandPlatform = struct {
    display: *c.wl_display,
    registry: *c.wl_registry,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    seat: ?*c.wl_seat = null,
    layer_shell: ?*c.zwlr_layer_shell_v1 = null,

    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.zwlr_layer_surface_v1 = null,
    keyboard: ?*c.wl_keyboard = null,

    // xkbcommon
    xkb_ctx: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,

    configured: bool = false,
    should_close: bool = false,
    width: u32 = constants.WIN_WIDTH,
    height: u32 = @intFromFloat(constants.SEARCH_BAR_HEIGHT),

    buffer: ?ShmBuffer = null,

    pending_keysym: u32 = c.XKB_KEY_NoSymbol,
    pending_text: ?[]const u8 = null,
    pending_text_buf: [32]u8 = undefined,
    has_pending_key: bool = false,

    pub fn init() !WaylandPlatform {
        const display = c.wl_display_connect(null) orelse return error.WaylandConnectFailed;
        
        const registry = c.wl_display_get_registry(display) orelse return error.RegistryFailed;

        var self = WaylandPlatform {
            .display = display,
            .registry = registry,
        };

        _ = c.wl_registry_add_listener(registry, &registry_listener, &self);
        _ = c.wl_display_roundtrip(display); 

        if (self.compositor == null) return error.NoCompositor;
        if (self.shm == null) return error.NoShm;
        if (self.layer_shell == null) return error.NoLayerShell;

        self.xkb_ctx = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);

        // NOTE: Surface, layer-surface, and keyboard listeners are NOT set up
        // here because `self` will be copied when returned by value. Calling
        // setupSurface() once the struct is at its final memory address.
        return self;
    }

    pub fn setupSurface(self: *WaylandPlatform) !void {
        if (self.seat) |seat| {
            self.keyboard = c.wl_seat_get_keyboard(seat);
        }

        self.surface = c.wl_compositor_create_surface(self.compositor.?) orelse return error.SurfaceCreationFailed;
        self.layer_surface = c.zwlr_layer_shell_v1_get_layer_surface(self.layer_shell.?, self.surface.?, null, c.ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "spotsearch") orelse return error.LayerSurfaceCreationFailed;

        c.zwlr_layer_surface_v1_set_size(self.layer_surface.?, self.width, self.height);
        //c.zwlr_layer_surface_v1_set_anchor(self.layer_surface.?, c.ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP);
        c.zwlr_layer_surface_v1_set_exclusive_zone(self.layer_surface.?, -1);
        c.zwlr_layer_surface_v1_set_keyboard_interactivity(self.layer_surface.?, c.ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
        c.zwlr_layer_surface_v1_set_margin(self.layer_surface.?, 100, 0, 0, 0);

        // Now `self` is stable — safe to pass as listener data.
        _ = c.zwlr_layer_surface_v1_add_listener(self.layer_surface.?, &layer_surface_listener, self);

        if (self.keyboard) |kb| {
            _ = c.wl_keyboard_add_listener(kb, &keyboard_listener, self);
        }

        // Restrict input to the window area only.
        self.updateInputRegion();

        c.wl_surface_commit(self.surface.?);
        _ = c.wl_display_roundtrip(self.display);
    }

    pub fn deinit(self: *WaylandPlatform) void {
        if (self.buffer) |*buf| buf.deinit();
        if (self.xkb_state) |s| c.xkb_state_unref(s);
        if (self.xkb_keymap) |k| c.xkb_keymap_unref(k);
        if (self.xkb_ctx) |ctx| c.xkb_context_unref(ctx);
        if (self.keyboard) |kb| c.wl_keyboard_destroy(kb);
        if (self.layer_surface) |ls| c.zwlr_layer_surface_v1_destroy(ls);
        if (self.surface) |s| c.wl_surface_destroy(s);
        if (self.seat) |seat| c.wl_seat_destroy(seat);
        if (self.layer_shell) |ls| c.zwlr_layer_shell_v1_destroy(ls);
        if (self.shm) |shm| c.wl_shm_destroy(shm);
        if (self.compositor) |comp| c.wl_compositor_destroy(comp);
        c.wl_registry_destroy(self.registry);
        c.wl_display_disconnect(self.display);
    }

    /// Set the input region of the surface to exactly the window area
    pub fn updateInputRegion(self: *WaylandPlatform) void {
        const comp = self.compositor orelse return;
        const surf = self.surface orelse return;
        const region = c.wl_compositor_create_region(comp) orelse return;
        c.wl_region_add(region, 0, 0, @intCast(self.width), @intCast(self.height));
        c.wl_surface_set_input_region(surf, region);
        c.wl_region_destroy(region);
    }

    pub fn ensureBuffer(self: *WaylandPlatform) !void {
        if (self.buffer) |*existing| {
            if (existing.width == self.width and existing.heigh == self.height) return;
            existing.deinit();
            self.buffer = null;
        }
        self.buffer = try ShmBuffer.create(self.shm.?, self.width, self.height);
    }

    pub fn commitFrame(self: *WaylandPlatform) void {
        if (self.buffer) |buf| {
            c.cairo_surface_flush(buf.cairo_surface);
            c.wl_surface_attach(self.surface.?, buf.wl_buffer, 0, 0);
            c.wl_surface_damage_buffer(self.surface.?, 0, 0, @intCast(self.width), @intCast(self.height));
            c.wl_surface_commit(self.surface.?);
        }
    }

    pub fn resize(self: *WaylandPlatform, new_height: u32) void {
        if (new_height == self.height) return;
        self.height = new_height;

        c.zwlr_layer_surface_v1_set_size(self.layer_surface.?, self.width, self.height);
        self.updateInputRegion();
        c.wl_surface_commit(self.surface.?);

        if (self.buffer) |*buf| {
            buf.deinit();
            self.buffer = null;
        }
    }

    /// Dispatch pending Wayland events and return a key event if one is ready.
    pub fn dispatchEvents(self: *WaylandPlatform) @import("../platform.zig").DispatchResult {
        if (self.should_close) return .close;
        _ = c.wl_display_dispatch(self.display);
        if (self.has_pending_key) {
            self.has_pending_key = false;
            return .{ .key = .{ .keysym = self.pending_keysym, .text = self.pending_text } };
        }
        if (!self.configured) return .expose;
        return .none;
    }

    fn processKey(self: *WaylandPlatform, key: u32) void {
        const xkb_keycode = key + 8;

        const state = self.xkb_state orelse return;

        self.pending_keysym = c.xkb_state_key_get_one_sym(state, xkb_keycode);

        const len = c.xkb_state_key_get_utf8(state, xkb_keycode, &self.pending_text_buf, self.pending_text_buf.len);
        if (len > 0 and len < self.pending_text_buf.len) {
            self.pending_text = self.pending_text_buf[0..@intCast(len)];
        } else {
            self.pending_text = null;
        }

        self.has_pending_key = true;
    }

    const registry_listener = c.wl_registry_listener {
        .global = handleRegistryGlobal,
        .global_remove = handleRegistryGlobalRemove,
    };

    fn handleRegistryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        const iface = std.mem.span(@as([*:0]const u8, @ptrCast(interface)));

        if (std.mem.eql(u8, iface, "wl_compositor")) {
            self.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, @min(version, 4)));
        } else if (std.mem.eql(u8, iface, "wl_shm")) {
            self.shm = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_shm_interface, 1));
        } else if (std.mem.eql(u8, iface, "wl_seat")) {
            self.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 5)));
        } else if (std.mem.eql(u8, iface, "zwlr_layer_shell_v1")) {
            self.layer_shell = @ptrCast(c.wl_registry_bind(registry, name, &c.zwlr_layer_shell_v1_interface, @min(version, 4)));
        }
    }

    fn handleRegistryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}

    const layer_surface_listener = c.zwlr_layer_surface_v1_listener {
        .configure = handleLayerConfigure,
        .closed = handleLayerClosed,
    };

    fn handleLayerConfigure(data: ?*anyopaque, layer_surface: ?*c.zwlr_layer_surface_v1, serial: u32, width: u32, height: u32) callconv(.c) void {
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        if (width > 0) self.width = width;
        if (height > 0) self.height = height;
        self.configured = true;
        c.zwlr_layer_surface_v1_ack_configure(layer_surface, serial);
    }

    fn handleLayerClosed(data: ?*anyopaque, _: ?*c.zwlr_layer_surface_v1) callconv(.c) void {
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        self.should_close = true;
    }

    const keyboard_listener = c.wl_keyboard_listener {
        .keymap = handleKeymap,
        .enter = handleKeyboardEnter,
        .leave = handleKeyboardLeave,
        .key = handleKeyPress,
        .modifiers = handleModifiers,
        .repeat_info = handleRepeatInfo,
    };

    fn handleKeymap(data: ?*anyopaque, _: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        defer std.posix.close(fd);

        if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;

        const map_ptr = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
        if (map_ptr == c.MAP_FAILED) return;
        defer _= c.munmap(map_ptr, size);

        const ctx = self.xkb_ctx orelse return;
        const keymap = c.xkb_keymap_new_from_string(ctx, @ptrCast(map_ptr), c.XKB_KEYMAP_FORMAT_TEXT_V1, c.XKB_KEYMAP_COMPILE_NO_FLAGS) orelse return;

        const state = c.xkb_state_new(keymap) orelse {
            c.xkb_keymap_unref(keymap);
            return;
        };

        if (self.xkb_state) |old| c.xkb_state_unref(old);
        if (self.xkb_keymap) |old| c.xkb_keymap_unref(old);
        self.xkb_keymap = keymap;
        self.xkb_state = state;
    }

    fn handleKeyboardEnter(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface, _: ?*c.wl_array) callconv(.c) void {
        std.debug.print("Keyboard focus gained\n", .{});
    } 

    fn handleKeyboardLeave(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface) callconv(.c) void {
        std.debug.print("Keyboard focus lost\n", .{});
    }

    fn handleKeyPress(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: u32, key: u32, state: u32) callconv(.c) void {
        if (state != c.WL_KEYBOARD_KEY_STATE_PRESSED) return;
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        self.processKey(key);
    }

    fn handleModifiers(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
        const self: *WaylandPlatform = @ptrCast(@alignCast(data));
        if (self.xkb_state) |state| {
            _ = c.xkb_state_update_mask(state, mods_depressed, mods_latched, mods_locked, 0, 0, group);
        }
    }

    fn handleRepeatInfo(_: ?*anyopaque, _: ?*c.wl_keyboard, _: i32, _: i32) callconv(.c) void {}
};
