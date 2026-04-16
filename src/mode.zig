const std = @import("std");
const c = @import("c.zig").c;

pub const RunMode = enum { oneshot, daemon };
pub const SessionType = enum { wayland, x11, tty };
pub const RunConfig = struct {
    mode: RunMode,
    session_type: SessionType,
};

pub fn parse() RunConfig {
    var config = RunConfig {
        .mode = RunMode.oneshot,
        .session_type = determineSessionType(),
    };

    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--deamon") or std.mem.eql(u8, arg, "-d")) {
            config.mode = .daemon;
        }
    }

    return config;
}

fn determineSessionType() SessionType {
    var s_type = SessionType.tty;
    const session_var = std.posix.getenv("XDG_SESSION_TYPE");
    const wayland_disp = std.posix.getenv("WAYLAND_DISPLAY");
    const disp = std.posix.getenv("DISPLAY");

    if (disp != null) {
        s_type = SessionType.x11;
    }
    if (session_var) |svar| {
        if (std.mem.eql(u8, svar, "x11")) {
            s_type = SessionType.x11;
        } else if (std.mem.eql(u8, svar, "wayland")) {
            s_type = SessionType.wayland;
        }
    }
    if (wayland_disp != null) {
        s_type = SessionType.wayland;
    }

    return s_type;
}
