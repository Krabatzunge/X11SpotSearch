const c = @import("c.zig").c;

pub const DateTime = struct {
    year: i32,
    month: i32,
    day: i32,
    hour: i32,
    minute: i32,
    second: i32,

    pub fn init() !DateTime {
        var now: c.time_t = undefined;
        _ = c.time(&now);

        var local_tm: c.tm = undefined;

        if (c.localtime_r(&now, &local_tm) == null) {
            return error.LocalTimeConversionFailed;
        }

        const year: i32 = @intCast(local_tm.tm_year + 1900);
        const month: i32 = @intCast(local_tm.tm_mon + 1);
        const day: i32 = @intCast(local_tm.tm_mday);
        const hour: i32 = @intCast(local_tm.tm_hour);
        const minute: i32 = @intCast(local_tm.tm_min);
        const second: i32 = @intCast(local_tm.tm_sec);

        return .{
            .year = year,
            .month = month,
            .day = day,
            .hour = hour,
            .minute = minute,
            .second = second,
        };
    }
};
