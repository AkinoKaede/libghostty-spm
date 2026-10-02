#!/bin/zsh
set -euo pipefail
SOURCE_DIR=${1:?Usage: 0019-keyword-highlighting.sh <source_dir>}
SCRIPT_DIR="$(cd "$(dirname "$0")/../../Script/support" && pwd)"
PYTHONPATH="$SCRIPT_DIR${PYTHONPATH:+:$PYTHONPATH}" python3 - "$SOURCE_DIR" <<'PYCODE'
import sys
from pathlib import Path
from anchored_edit import Source
root = sys.argv[1]
keyword_source = r'''//! Render-only keyword colors. The terminal grid and copied text are untouched.
const std = @import("std");
const oni = @import("oniguruma");
const terminal = @import("../terminal/main.zig");
const Allocator = std.mem.Allocator;
pub const Colors = struct {
    foreground: ?terminal.color.RGB = null,
    background: ?terminal.color.RGB = null,
};
pub const CellMap = std.AutoHashMapUnmanaged(terminal.point.Coordinate, Colors);
pub const max_rules = 64;
pub const max_pattern_bytes = 16384;

pub fn compile(pattern: []const u8) !oni.Regex {
    if (pattern.len == 0 or pattern.len > max_pattern_bytes or std.mem.indexOfScalar(u8, pattern, 0) != null)
        return error.InvalidKeywordPattern;
    return oni.Regex.init(pattern, .{}, oni.Encoding.utf8, oni.Syntax.default, null);
}

pub const Rule = struct {
    regex: oni.Regex,
    colors: Colors,

    pub fn init(value: []const u8) !Rule {
        // foreground,background:regex; a dash leaves that channel unchanged.
        const colon = std.mem.indexOfScalar(u8, value, ':') orelse return error.InvalidKeywordColor;
        const comma = std.mem.indexOfScalar(u8, value[0..colon], ',') orelse return error.InvalidKeywordColor;
        const foreground = try parseColor(value[0..comma]);
        const background = try parseColor(value[comma + 1 .. colon]);
        return .{ .regex = try compile(value[colon + 1 ..]), .colors = .{ .foreground = foreground, .background = background } };
    }
};

fn parseColor(value: []const u8) !?terminal.color.RGB {
    if (std.mem.eql(u8, value, "-")) return null;
    if (value.len != 6) return error.InvalidKeywordColor;
    return try terminal.color.RGB.parse(value);
}

pub const Set = struct {
    rules: []Rule,

    pub fn init(alloc: Allocator, values: []const [:0]const u8) !Set {
        if (values.len > max_rules) return error.TooManyKeywordRules;
        var rules: std.ArrayList(Rule) = .empty;
        errdefer {
            for (rules.items) |*rule| rule.regex.deinit();
            rules.deinit(alloc);
        }
        for (values) |value| {
            var rule = try Rule.init(value);
            errdefer rule.regex.deinit();
            try rules.append(alloc, rule);
        }
        return .{ .rules = try rules.toOwnedSlice(alloc) };
    }

    pub fn deinit(self: *Set, alloc: Allocator) void {
        for (self.rules) |*rule| rule.regex.deinit();
        alloc.free(self.rules);
    }

    pub fn renderCellMap(self: *Set, alloc: Allocator, state: *const terminal.RenderState) !CellMap {
        var result: CellMap = .empty;
        errdefer result.deinit(alloc);
        if (self.rules.len == 0) return result;
        var builder: std.Io.Writer.Allocating = .init(alloc);
        defer builder.deinit();
        var map: terminal.RenderState.StringMap = .empty;
        defer map.deinit(alloc);
        try writeText(alloc, state, &builder.writer, &map);
        const text = builder.writer.buffered();
        // Bound both input and Oniguruma's backtracking, even for user patterns.
        if (text.len > 262144) return result;
        var param = try oni.MatchParam.init();
        defer param.deinit();
        try param.setRetryLimitInSearch(10000);
        for (self.rules) |*rule| {
            var region: oni.Region = .{};
            defer region.deinit();
            var offset: usize = 0;
            var iterations: usize = 0;
            while (offset < text.len and iterations < 4096) : (iterations += 1) {
                _ = rule.regex.searchAdvancedWithParam(text, offset, text.len, &region, .{}, &param) catch break;
                const start: usize = @intCast(region.starts()[0]);
                const end: usize = @intCast(region.ends()[0]);
                if (end > start) {
                    for (map.items[start..end]) |cell| {
                        if (cell.x >= state.cols) continue; // Synthetic newline.
                        const entry = try result.getOrPut(alloc, cell);
                        if (!entry.found_existing) entry.value_ptr.* = rule.colors;
                    }
                    offset = end;
                } else {
                    // Skip a complete UTF-8 scalar after an empty match.
                    offset = end + 1;
                    while (offset < text.len and text[offset] & 0xc0 == 0x80) : (offset += 1) {}
                }
            }
        }
        return result;
    }
};

// Unlike link search, text rules need spaces for empty cells and must omit
// wide-character spacer cells. Keep the byte map aligned with actual glyphs.
fn writeText(alloc: Allocator, state: *const terminal.RenderState, writer: *std.Io.Writer, map: *terminal.RenderState.StringMap) !void {
    const rows = state.row_data.slice();
    const start = state.viewportStart();
    for (rows.items(.raw)[start..][0..state.rows], rows.items(.cells)[start..][0..state.rows], 0..) |row, cells, y| {
        const slice = cells.slice();
        const raw = slice.items(.raw);
        var end = raw.len;
        if (!row.wrap) {
            while (end > 0 and raw[end - 1].codepoint() == 0 and raw[end - 1].wide == .narrow) end -= 1;
        }
        for (raw[0..end], slice.items(.grapheme)[0..end], 0..) |cell, graphemes, x| {
            if (cell.wide == .spacer_head or cell.wide == .spacer_tail) continue;
            const cp = if (cell.codepoint() == 0) ' ' else cell.codepoint();
            var len: usize = try std.unicode.utf8CodepointSequenceLength(cp);
            try writer.print("{u}", .{cp});
            if (cell.hasGrapheme()) {
                for (graphemes) |extra| {
                    len += try std.unicode.utf8CodepointSequenceLength(extra);
                    try writer.print("{u}", .{extra});
                }
            }
            try map.appendNTimes(alloc, .{ .x = @intCast(x), .y = @intCast(y) }, len);
        }
        if (!row.wrap) {
            try writer.writeByte('\n');
            try map.append(alloc, .{ .x = state.cols, .y = @intCast(y) });
        }
    }
}

test "keyword highlighting maps wrapped wide text and preserves boundaries" {
    const t = std.testing;
    try oni.testing.ensureInit();
    var term = try terminal.Terminal.init(t.io, t.allocator, .{ .cols = 12, .rows = 5 });
    defer term.deinit(t.allocator);
    var stream = term.vtStream();
    defer stream.deinit();
    stream.nextSlice("\xe4\xb8\xad Error: Warn error\r\nWARNING prewarning\r\nERROR");
    var state: terminal.RenderState = .empty;
    defer state.deinit(t.allocator);
    try state.update(t.allocator, &term);
    var set = try Set.init(t.allocator, &.{
        "FF0000,-:\\b(?=[A-Za-z]*[A-Z])(?i:error|warn(?:ing)?)\\b",
        "00FF00,-:Error",
    });
    defer set.deinit(t.allocator);
    var colors = try set.renderCellMap(t.allocator, &state);
    defer colors.deinit(t.allocator);
    try t.expectEqual(terminal.color.RGB{ .r = 255, .g = 0, .b = 0 }, colors.get(.{ .x = 3, .y = 0 }).?.foreground.?);
    try t.expect(colors.get(.{ .x = 0, .y = 0 }) == null);
    // Five Error cells, four Warn cells, seven WARNING cells, five ERROR cells.
    try t.expectEqual(@as(usize, 21), colors.count());
}

test "keyword highlighting empty and pathological patterns terminate" {
    const t = std.testing;
    try oni.testing.ensureInit();
    var term = try terminal.Terminal.init(t.io, t.allocator, .{ .cols = 80, .rows = 2 });
    defer term.deinit(t.allocator);
    var stream = term.vtStream();
    defer stream.deinit();
    stream.nextSlice("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!");
    var state: terminal.RenderState = .empty;
    defer state.deinit(t.allocator);
    try state.update(t.allocator, &term);
    var set = try Set.init(t.allocator, &.{ "FF0000,-:(?:)", "00FF00,-:(a+)+$", "0000FF,-:!" });
    defer set.deinit(t.allocator);
    var colors = try set.renderCellMap(t.allocator, &state);
    defer colors.deinit(t.allocator);
    try t.expectEqual(@as(usize, 1), colors.count());
}

test "keyword highlighting matches Unicode graphemes spaces and line anchors" {
    const t = std.testing;
    try oni.testing.ensureInit();
    var term = try terminal.Terminal.init(t.io, t.allocator, .{ .cols = 10, .rows = 3 });
    defer term.deinit(t.allocator);
    var stream = term.vtStream();
    defer stream.deinit();
    stream.nextSlice("中e\xcc\x81 Error\r\nX\x1b[2CWarn");
    var state: terminal.RenderState = .empty;
    defer state.deinit(t.allocator);
    try state.update(t.allocator, &term);
    var set = try Set.init(t.allocator, &.{ "FF0000,-:中e\xcc\x81 Error$", "00FF00,-:X  Warn$" });
    defer set.deinit(t.allocator);
    var colors = try set.renderCellMap(t.allocator, &state);
    defer colors.deinit(t.allocator);
    try t.expect(colors.get(.{ .x = 0, .y = 0 }) != null);
    try t.expect(colors.get(.{ .x = 2, .y = 0 }) != null);
    try t.expect(colors.get(.{ .x = 3, .y = 1 }) != null);
    try t.expectEqual(@as(usize, 15), colors.count());
}

test "keyword highlighting supports background only and unchanged channels" {
    const t = std.testing;
    try oni.testing.ensureInit();
    var term = try terminal.Terminal.init(t.io, t.allocator, .{ .cols = 20, .rows = 2 });
    defer term.deinit(t.allocator);
    var stream = term.vtStream();
    defer stream.deinit();
    stream.nextSlice("Error Warn OK");
    var state: terminal.RenderState = .empty;
    defer state.deinit(t.allocator);
    try state.update(t.allocator, &term);
    var set = try Set.init(t.allocator, &.{ "-,112233:Error", "445566,778899:Warn", "-,-:OK", "FFFFFF,FFFFFF:Error|Warn|OK" });
    defer set.deinit(t.allocator);
    var colors = try set.renderCellMap(t.allocator, &state);
    defer colors.deinit(t.allocator);
    const err = colors.get(.{ .x = 0, .y = 0 }).?;
    try t.expect(err.foreground == null);
    try t.expectEqual(terminal.color.RGB{ .r = 0x11, .g = 0x22, .b = 0x33 }, err.background.?);
    const warn = colors.get(.{ .x = 6, .y = 0 }).?;
    try t.expectEqual(terminal.color.RGB{ .r = 0x44, .g = 0x55, .b = 0x66 }, warn.foreground.?);
    try t.expectEqual(terminal.color.RGB{ .r = 0x77, .g = 0x88, .b = 0x99 }, warn.background.?);
    const ok = colors.get(.{ .x = 11, .y = 0 }).?;
    try t.expect(ok.foreground == null and ok.background == null);
    try t.expectError(error.InvalidKeywordColor, Rule.init("1000000,-:Error"));
}
'''
path = Path(root) / "src/renderer/keyword.zig"
if path.exists() and path.read_text() != keyword_source:
    raise SystemExit("[-] keyword.zig differs from the owned keyword highlighting patch")
path.write_text(keyword_source)
config = Source(root, "src/config/Config.zig")
config.insert_after('link: RepeatableLink = .{},', '\n\n/// Ordered render-only foreground/background colors, formatted as foreground,background:regex.\n@"keyword-highlight": RepeatableKeywordHighlight = .{},', marker='@"keyword-highlight": RepeatableKeywordHighlight = .{},')
config.insert_before('pub const RepeatableString = struct {', r'''pub const RepeatableKeywordHighlight = struct {
    values: RepeatableString = .{},
    pub fn parseCLI(self: *@This(), alloc: Allocator, input: ?[]const u8) !void {
        const value = input orelse return error.ValueRequired;
        if (value.len > 0) {
            if (self.values.count() >= 64) return error.TooManyKeywordRules;
            var rule = try @import("../renderer/keyword.zig").Rule.init(value);
            defer rule.regex.deinit();
        }
        try self.values.parseCLI(alloc, input);
    }
    pub fn clone(self: *const @This(), alloc: Allocator) Allocator.Error!@This() {
        return .{ .values = try self.values.clone(alloc) };
    }
    pub fn equal(self: @This(), other: @This()) bool { return self.values.equal(other.values); }
    pub fn formatEntry(self: @This(), formatter: formatterpkg.EntryFormatter) !void {
        try self.values.formatEntry(formatter);
    }
};

''')
config.save()
renderer = Source(root, "src/renderer/generic.zig")
renderer.insert_after('const link = @import("link.zig");', '\nconst keyword = @import("keyword.zig");')
renderer.insert_before('        const HighlightTag = enum(u8) {', '        keyword_cells: keyword.CellMap = .empty,\n\n')
renderer.insert_after('            links: link.Set,', '\n            keyword_highlights: keyword.Set,')
renderer.insert_after('                self.links.deinit(alloc);', '\n                self.keyword_highlights.deinit(alloc);')
renderer.insert_after('                    config.link.links.items,\n                );', '\n                var owned_links = links;\n                errdefer owned_links.deinit(alloc);\n                const keyword_highlights = try keyword.Set.init(alloc, config.@"keyword-highlight".values.list.items);')
renderer.replace('                    .links = links,\n                    .vsync', '                    .links = links,\n                    .keyword_highlights = keyword_highlights,\n                    .vsync')
renderer.insert_before('            self.api.deinit();', '            self.keyword_cells.deinit(self.alloc);\n', marker='            self.keyword_cells.deinit(self.alloc);\n            self.api.deinit();')
renderer.insert_after('            const state: *terminal.RenderState = &self.terminal_state;', r'''

            if (state.dirty != .false) {
                const colors: keyword.CellMap = self.config.keyword_highlights.renderCellMap(self.alloc, state) catch .empty;
                const had_colors = self.keyword_cells.count() > 0;
                self.keyword_cells.deinit(self.alloc);
                self.keyword_cells = colors;
                // A match can cross soft-wrapped rows; all affected glyphs must be rebuilt.
                if (had_colors or colors.count() > 0) state.dirty = .full;
            }
''')
renderer.insert_after('                const fg = fg: {', r'''
                    if (selected == .false) {
                        if (keyword_colors) |colors| {
                            if (colors.foreground) |color| break :fg color;
                        }
                    }
''')
renderer.replace('const bg = switch (selected) {', r'''const keyword_x = if (wide == .spacer_tail) x -| 1 else x;
                const keyword_colors = self.keyword_cells.get(.{ .x = @intCast(keyword_x), .y = y });
                const keyword_bg = if (selected == .false and keyword_colors != null) keyword_colors.?.background else null;
                const bg = if (keyword_bg) |color| color else switch (selected) {''')
renderer.replace('if (selected != .false) break :bg_alpha default;', 'if (selected != .false or keyword_bg != null) break :bg_alpha default;')
renderer.save()
header = Source(root, "include/ghostty.h")
header.insert_before('GHOSTTY_API ghostty_info_s ghostty_info(void);', r'''// Returns a borrowed diagnostic string; an empty string means the regex is valid.
// Call ghostty_init before using this API. Do not free the returned string.
GHOSTTY_API ghostty_string_s ghostty_keyword_highlight_validate(const uint8_t*, uintptr_t);
''')
header.save()
embedded = Source(root, "src/apprt/embedded.zig")
embedded.insert_after('pub const CAPI = struct {', r'''
    export fn ghostty_keyword_highlight_validate(pattern: [*]const u8, len: usize) String {
        var regex = @import("../renderer/keyword.zig").compile(pattern[0..len]) catch |err| {
            return String.fromSlice(@errorName(err));
        };
        regex.deinit();
        return String.empty;
    }
''')
embedded.save()
PYCODE
