pub const c = @cImport({
    @cInclude("xcb/xcb.h");
    @cInclude("xcb/xcb_icccm.h");
    @cInclude("xcb/xcb_ewmh.h");
    @cInclude("xcb/xkb.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-x11.h");
    @cInclude("cairo/cairo.h");
    @cInclude("cairo/cairo-xcb.h");
    @cInclude("pango/pangocairo.h");
    @cInclude("string.h");
    @cInclude("poll.h");
    @cInclude("librsvg/rsvg.h");
    @cInclude("sys/timerfd.h");
});
