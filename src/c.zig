const build_options = @import("build_options");

pub const c = @cImport({
    // Shared
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("cairo/cairo.h");
    @cInclude("pango/pangocairo.h");
    @cInclude("librsvg/rsvg.h");
    @cInclude("curl/curl.h");
    @cInclude("poll.h");
    @cInclude("sys/timerfd.h");
    @cInclude("time.h");
    @cInclude("string.h");
    @cInclude("gdk-pixbuf/gdk-pixbuf.h");

    // X11
    if (build_options.enable_x11) {
        @cInclude("xcb/xcb.h");
        @cInclude("xcb/xcb_icccm.h");
        @cInclude("xcb/xcb_ewmh.h");
        @cInclude("xcb/xkb.h");
        @cInclude("xkbcommon/xkbcommon-x11.h");
        @cInclude("cairo/cairo-xcb.h");
    }

    if (build_options.enable_wayland) {
        @cInclude("wayland-client.h");
        @cInclude("wlr-layer-shell-unstable-v1-client-protocol.h");
        @cInclude("sys/mman.h");
        @cInclude("fcntl.h");
    }
});
