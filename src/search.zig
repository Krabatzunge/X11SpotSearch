const std = @import("std");
const DesktopEntry = @import("desktop.zig").DesktopEntry;
const SearchEngine = @import("config/config.zig").SearchEngine;

pub const ScoredEntry = struct {
    entry: *const DesktopEntry,
    score: i32,
};

pub const SearchTag = enum {
    Name,
    Description,
    Category, //TODO: Implement category search
    Unspecified,

    pub fn getSearchPattern(self: SearchTag) []const u8 {
        return switch (self) {
            .Name => "name",
            .Description => "desc",
            .Category => "cat",
            .Unspecified => "",
        };
    }
};
// Longest SearchTag [11]const u8
// use @tagName(tag) to get SearchTag as []const u8

pub const SearchResult = struct {
    entries: []ScoredEntry,
    tag: SearchTag,
    query: []const u8,
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

pub fn startsWithTag(pattern: []const u8) bool {
    if (pattern.len==0) return false;
    return pattern[0] == '#' or pattern[0] == '@' or pattern[0] == '$' or pattern[0] == '~';
    // # = search tag || @ = action || $ = widget || ~ = search engine
}

/// Specifies a SearchTag from the pattern and writes a tag free pattern to a buffer
/// Returns Unspecified (search across all tags) when no tag was found
fn extractSearchTag(pattern: []const u8) struct { tag: SearchTag, cleaned: []const u8 } {
    var tag = SearchTag.Unspecified;

    if (std.mem.startsWith(u8, pattern[1..], SearchTag.Name.getSearchPattern())) {
        tag = SearchTag.Name;
    } else if (std.mem.startsWith(u8, pattern[1..], SearchTag.Description.getSearchPattern())) {
        tag = SearchTag.Description;
    } else if (std.mem.startsWith(u8, pattern[1..], SearchTag.Category.getSearchPattern())) {
        tag = SearchTag.Category;
    }

    if (tag == SearchTag.Unspecified) {
        return .{ .tag = tag, .cleaned = pattern };
    }

    const tagEnd: usize = 1 + tag.getSearchPattern().len;
    if (pattern.len <= tagEnd) {
        return .{ .tag = tag, .cleaned = pattern[tagEnd..] };
    }

    const contentStart: usize = tagEnd + 1;
    if (pattern[tagEnd] != ' ') {
        return .{ .cleaned = pattern[tagEnd..], .tag = tag };
    }

    return .{ .cleaned = pattern[contentStart..], .tag = tag };
}

fn extractSearchEngine(pattern: []const u8, search_engines: []const SearchEngine) struct {name: []const u8, cleaned: []const u8} {
    var name: []const u8 = "";
    var found_in_engines = false;

    for (search_engines) |engine| {
        if (engine.name.len == 0 or engine.name.len > 128) continue;
        if (pattern.len <= engine.name.len) continue;
        if (std.ascii.eqlIgnoreCase(pattern[1..1+engine.name.len], engine.name)) {
            name = engine.name;
            found_in_engines = true;
            break;
        }
    }

    if (!found_in_engines) {
        if (pattern.len > 3 and std.ascii.eqlIgnoreCase(pattern[1..4], "web")) {
            name = "web";
        }
    }

    const engineEnd: usize = 1 + name.len; 
    if (pattern.len <= engineEnd) {
        return .{ .name = name, .cleaned = pattern[engineEnd..] };
    }

    const contentStart: usize = engineEnd + 1;
    if (pattern[engineEnd] != ' ') {
        return .{ .name = name, .cleaned = pattern[engineEnd..] };
    }

    return .{ .name = name, .cleaned = pattern[contentStart..] };
}

fn extractPrefixLogic(pattern: []const u8, search_engines: []const SearchEngine) struct {tag: SearchTag, cleaned: []const u8, engine_name: []const u8} {
   if (pattern.len == 0 or !startsWithTag(pattern)) {
        return .{ .tag = .Unspecified, .cleaned = pattern, .engine_name = undefined};
   } 

   if (pattern[0] == '#') {
       const search_tag_res = extractSearchTag(pattern);
       return .{ .engine_name = undefined, .tag = search_tag_res.tag, .cleaned = search_tag_res.cleaned };
   }

   if (pattern[0] == '~') {
       const search_engine_res = extractSearchEngine(pattern, search_engines);
       return .{ .engine_name = search_engine_res.name, .cleaned = search_engine_res.cleaned, .tag = .Unspecified };
   }

    return .{ .tag = .Unspecified, .cleaned = pattern, .engine_name = undefined};
}

/// Search entries and return up to max_result, sorted by score descending.
pub fn search(entries: []const DesktopEntry, search_engines: []const SearchEngine, pattern: []const u8, result_buf: []ScoredEntry) SearchResult {
    var count: usize = 0;

    const prefix_extraction_res = extractPrefixLogic(pattern, search_engines);
    const search_tag = prefix_extraction_res.tag;
    const engine_name = prefix_extraction_res.engine_name;
    const cleaned_pattern = prefix_extraction_res.cleaned; 

    _ = engine_name;

    const use_name: bool = (search_tag == SearchTag.Unspecified or search_tag == SearchTag.Name);
    const use_desc: bool = (search_tag == SearchTag.Unspecified or search_tag == SearchTag.Description);
    const description_penalty: i32 = if (search_tag == SearchTag.Description) 0 else 2;

    for (entries) |*entry| {
        const name_score: ?i32 = if (use_name) fuzzyScore(cleaned_pattern, entry.name) else null;
        const comment_score: ?i32 = if (use_desc) fuzzyScore(cleaned_pattern, entry.comment) else null;

        // Prefer name over comment
        const score = blk: {
            if (name_score) |ns| {
                if (comment_score) |cs| {
                    break :blk @max(ns, cs - description_penalty);
                }
                break :blk ns;
            }
            if (comment_score) |cs| break :blk cs - description_penalty;
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

    return .{
        .entries = result_buf[0..count],
        .tag = search_tag,
        .query = cleaned_pattern,
    };
}
