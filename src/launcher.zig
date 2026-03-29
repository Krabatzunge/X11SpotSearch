const std = @import("std");
const DesktopEntry = @import("desktop.zig").DesktopEntry;

pub const LaunchError = error{
    ExecEmpty,
    ForkFailed,
    CommandTolong,
};

/// Launch deskop entry's command, detached form launcher process.
/// Double-forks so that launched app is reparented to PID 1 and survives
pub fn launch(entry: *const DesktopEntry) LaunchError!void {
    var cmd_buf: [4096]u8 = undefined;
    const cmd = entry.getCommand(&cmd_buf) orelse return LaunchError.ExecEmpty;

    if (cmd.len + 1 >= cmd_buf.len) return LaunchError.CommandTolong;
    cmd_buf[cmd.len] = 0;

    const argv = [_:null]?[*:0]const u8{
        "/bin/sh",
        "-c",
        @ptrCast(cmd_buf[0..cmd.len :0].ptr),
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
