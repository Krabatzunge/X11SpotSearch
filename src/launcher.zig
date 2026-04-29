const std = @import("std");
const DesktopEntry = @import("desktop.zig").DesktopEntry;

pub const LaunchError = error{
    ExecEmpty,
    ForkFailed,
    CommandTolong,
};

pub fn launchDesktopEntry(entry: *const DesktopEntry) LaunchError!void {
    var cmd_buf: [4096]u8 = undefined;
    const cmd = entry.getCommand(&cmd_buf) orelse return LaunchError.ExecEmpty;

    if (cmd.len + 1 >= cmd_buf.len) return LaunchError.CommandTolong;
    cmd_buf[cmd.len] = 0;

    try launch(cmd_buf, cmd.len);
}

pub fn launchWebSearch(search: []const u8, engine_path: []const u8) LaunchError!void {
    var search_buf: [256]u8 = undefined;
    if (search.len > search_buf.len) return LaunchError.CommandTolong;
    @memcpy(search_buf[0..search.len], search);
    const normalized_search = search_buf[0..search.len];
    std.mem.replaceScalar(u8, normalized_search, ' ', '+');

    var search_url_buf: [512]u8 = undefined;
    const search_url_len = std.mem.replacementSize(u8, engine_path, "{s}", normalized_search);
    if (search_url_len > search_url_buf.len) return LaunchError.CommandTolong;
    _ = std.mem.replace(u8, engine_path, "{s}", normalized_search, search_url_buf[0..search_url_len]);
    const search_url = search_url_buf[0..search_url_len];

    var cmd_buf: [4096]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "xdg-open \"{s}\"", .{search_url}) catch return LaunchError.CommandTolong;

    if (cmd.len + 1 >= cmd_buf.len) return LaunchError.CommandTolong;
    cmd_buf[cmd.len] = 0;

    try launch(cmd_buf, cmd.len);
}

/// Launch command, detached form launcher process.
/// Double-forks so that launched app is reparented to PID 1 and survives
pub fn launch(cmd_buf: [4096] u8, cmd_len: usize) LaunchError!void {

    const argv = [_:null]?[*:0]const u8{
        "/bin/sh",
        "-c",
        @ptrCast(cmd_buf[0..cmd_len :0].ptr),
        null,
    };

    const pid = std.posix.fork() catch return LaunchError.ForkFailed;

    if (pid == 0) {
        _ = std.posix.setsid() catch {};

        const pid2 = std.posix.fork() catch std.posix.exit(1);

        if (pid2 == 0) {
            const devnull = std.posix.open(
                "/dev/null",
                .{ .ACCMODE = .RDWR },
                0,
            ) catch std.posix.exit(1);

            std.posix.dup2(devnull, 0) catch {};
            std.posix.dup2(devnull, 1) catch {};
            std.posix.dup2(devnull, 2) catch {};
            if (devnull > 2) std.posix.close(devnull);

            switch (std.posix.execvpeZ("/bin/sh", &argv, @ptrCast(std.c.environ))) {
                else => std.posix.exit(1),
            }
        } else {
            std.posix.exit(0);
        }
    } else {
        _ = std.posix.waitpid(pid, 0);
    }
}
