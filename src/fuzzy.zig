const std = @import("std");
const DesktopEntry = @import("desktop.zig").DesktopEntry;

pub const ScoredEntry = struct {
    entry: *const DesktopEntry,
    score: i32,
};

/// Fuzzy match
/// Rewards
///  - Consecutive character matches
///  - Matches at word boundaries (after space, hyphen, or start)
///  - Matches at the start of the string
/// Penalizes:
///  - Gaps between matches
pub fn fuzzyScore(pattern: []const u8, text: []const u8) ?i32 {
    if (pattern.len == 0) return 0;
    if (pattern.len > text.len) return null;

    var score: i32 = 0;
    var pattern_idx: usize = 0;
    var prev_match_idx: ?usize = null;
    var consecutive: i32 = 0;

    for (text, 0..) |text_char, text_idx| {
        if (pattern_idx >= pattern.len) break;

        const tc = std.ascii.toLower(text_char);
        const pc = std.ascii.toLower(pattern[pattern_idx]);

        if (tc == pc) {
            // Base Score
            score += 1;

            // Consecutive bonus
            if (prev_match_idx) |prev| {
                if (text_idx == prev + 1) {
                    consecutive += 1;
                    score += consecutive * 2;
                } else {
                    consecutive = 0;
                    const gap: i32 = @intCast(text_idx - prev - 1);
                    score -= @min(gap, 3);
                }
            }

            // Start-of-string bonus
            if (text_idx == 0) score += 5;

            // Word boundary bonus (after space, hyphen, or underline)
            if (text_idx > 0) {
                const prev_char = text[text_idx - 1];
                if (prev_char == ' ' or prev_char == '-' or prev_char == '_') {
                    score += 3;
                }
            }

            prev_match_idx = text_idx;
            pattern_idx += 1;
        }
    }

    if (pattern_idx < pattern.len) return null;

    return score;
}

/// Search entries and return up to max_result, sorted by score descending.
pub fn search(entries: []const DesktopEntry, pattern: []const u8, result_buf: []ScoredEntry) []ScoredEntry {
    var count: usize = 0;

    for (entries) |*entry| {
        const name_score = fuzzyScore(pattern, entry.name);
        const comment_score = fuzzyScore(pattern, entry.comment);

        // Prefer name over comment
        const score = blk: {
            if (name_score) |ns| {
                if (comment_score) |cs| {
                    break :blk @max(ns, cs - 2);
                }
                break :blk ns;
            }
            if (comment_score) |cs| break :blk cs - 2;
            break :blk @as(?i32, null);
        };

        if (score) |s| {
            if (count < result_buf.len) {
                result_buf[count] = .{ .entry = entry, .score = s };
                count += 1;
            } else {
                var min_idx: usize = 0;
                for (result_buf[0..count], 0..) |r, i| {
                    if (r.score < result_buf[min_idx].score) min_idx = i;
                }
                if (s > result_buf[min_idx].score) {
                    result_buf[min_idx] = .{ .entry = entry, .score = s };
                }
            }
        }
    }

    std.mem.sort(ScoredEntry, result_buf[0..count], {}, struct {
        fn lessThan(_: void, a: ScoredEntry, b: ScoredEntry) bool {
            return a.score > b.score;
        }
    }.lessThan);

    return result_buf[0..count];
}
