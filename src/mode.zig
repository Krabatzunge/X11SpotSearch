const std = @import("std");
const c = @import("c.zig").c;

pub const Mode = enum { oneshot, daemon };

pub fn parse() Mode {
    var mode = Mode.oneshot;

    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--deamon") or std.mem.eql(u8, arg, "-d")) {
            mode = .daemon;
        }
    }

    return mode;
}
