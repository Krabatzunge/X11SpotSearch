const c = @import("c.zig").c;

pub fn armTimer(timer_fd: c_int, initial_ms: u32, repeat_ms: u32) void {
    const ms_to_ns = 1_000_000;
    const its = c.struct_itimerspec{
        .it_value = .{
            .tv_sec = 0,
            .tv_nsec = @as(c_long, initial_ms) * ms_to_ns,
        },
        .it_interval = .{
            .tv_sec = 0,
            .tv_nsec = @as(c_long, repeat_ms) * ms_to_ns,
        },
    };
    _ = c.timerfd_settime(timer_fd, 0, &its, null);
}
