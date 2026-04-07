const std = @import("std");

pub const Detector = struct {
    ctx: *anyopaque,
    matches: *const fn (ctx: *anyopaque, query: []const u8) bool,
};

pub const KeywordDetector = struct {
    keyword: []const u8,

    pub fn create(keyword: []const u8) KeywordDetector {
        return .{ .keyword = keyword };
    }

    pub fn asDetector(self: *KeywordDetector) Detector {
        return .{
            .ctx = self,
            .matches = matches,
        };
    }

    fn matches(ctx: *anyopaque, query: []const u8) bool {
        const self: *KeywordDetector = @ptrCast(@alignCast(ctx));
        var iter = std.mem.tokenizeScalar(u8, query, ' ');
        while (iter.next()) |word| {
            var buf: [64]u8 = undefined;
            if (word.len > buf.len) continue;
            const lower = std.ascii.lowerString(buf[0..word.len], word);
            if (std.mem.eql(u8, lower, self.keyword)) return true;
        }
        return false;
    }
};
