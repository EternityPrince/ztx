const std = @import("std");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;
const number_format = @import("number_format.zig");

const ExtRow = struct {
    ext: []const u8,
    stat: model.ExtensionStat,
};

const TypeRow = struct {
    rank: usize,
    ext: []const u8,
    files: usize,
    lines: usize,
    bytes: usize,
};

const top_types_limit: usize = 10;

pub fn printStats(writer: anytype, result: *const model.ScanResult, context: RenderContext) !void {
    const style = context.style;

    try style.write(writer, ansi.section, "SUMMARY\n");
    try printMetric(writer, style, "Files", result.total_files);
    try printMetric(writer, style, "Dirs", result.total_dirs);
    try printMetric(writer, style, "Lines", result.total_lines);
    try printMetric(writer, style, "Bytes", result.total_bytes);
    try printAverageMetric(writer, style, "Avg lines/file", result.total_lines, result.total_files);
    try printAverageMetric(writer, style, "Avg bytes/file", result.total_bytes, result.total_files);

    try writer.writeAll("\n");
    try style.write(writer, ansi.section, "FILE TYPES (Top 10 by files)\n");

    var rows = std.ArrayList(ExtRow).empty;
    defer rows.deinit(std.heap.page_allocator);

    var iterator = result.ext_stats.iterator();
    while (iterator.next()) |ext| {
        try rows.append(std.heap.page_allocator, .{
            .ext = ext.key_ptr.*,
            .stat = ext.value_ptr.*,
        });
    }

    std.mem.sort(ExtRow, rows.items, {}, extRowLessThan);

    const shown = @min(rows.items.len, top_types_limit);
    var shown_files: usize = 0;
    var shown_lines: usize = 0;
    var shown_bytes: usize = 0;

    var type_rows = std.ArrayList(TypeRow).empty;
    defer type_rows.deinit(std.heap.page_allocator);

    for (rows.items[0..shown], 0..) |row, idx| {
        shown_files += row.stat.count;
        shown_lines += row.stat.total_lines;
        shown_bytes += row.stat.total_bytes;
        try type_rows.append(std.heap.page_allocator, .{
            .rank = idx + 1,
            .ext = row.ext,
            .files = row.stat.count,
            .lines = row.stat.total_lines,
            .bytes = row.stat.total_bytes,
        });
    }

    if (rows.items.len > top_types_limit) {
        const others_files = result.total_files - shown_files;
        const others_lines = result.total_lines - shown_lines;
        const others_bytes = result.total_bytes - shown_bytes;
        try type_rows.append(std.heap.page_allocator, .{
            .rank = 0,
            .ext = "others",
            .files = others_files,
            .lines = others_lines,
            .bytes = others_bytes,
        });
    }

    try printTypeTable(writer, style, type_rows.items);

    try writer.writeAll("\n");
    try style.write(writer, ansi.section, "SKIPPED\n");
    var has_skipped = false;
    if (result.skipped.gitignore > 0) {
        try printMetric(writer, style, "gitignore", result.skipped.gitignore);
        has_skipped = true;
    }
    if (result.skipped.builtin > 0) {
        try printMetric(writer, style, "builtin", result.skipped.builtin);
        has_skipped = true;
    }
    if (result.skipped.binary_or_unsupported > 0) {
        try printMetric(writer, style, "binary/unsupported", result.skipped.binary_or_unsupported);
        has_skipped = true;
    }
    if (result.skipped.size_limit > 0) {
        try printMetric(writer, style, "size limit", result.skipped.size_limit);
        has_skipped = true;
    }
    if (result.skipped.content_policy > 0) {
        try printMetric(writer, style, "content policy", result.skipped.content_policy);
        has_skipped = true;
    }
    if (result.skipped.depth_limit > 0) {
        try printMetric(writer, style, "depth limit", result.skipped.depth_limit);
        has_skipped = true;
    }
    if (result.skipped.file_limit > 0) {
        try printMetric(writer, style, "file limit", result.skipped.file_limit);
        has_skipped = true;
    }
    if (result.skipped.symlink > 0) {
        try printMetric(writer, style, "symlink", result.skipped.symlink);
        has_skipped = true;
    }
    if (result.skipped.permission > 0) {
        try printMetric(writer, style, "permission", result.skipped.permission);
        has_skipped = true;
    }

    if (!has_skipped) {
        try writer.writeAll("  ");
        try style.write(writer, ansi.label, "none");
        try writer.writeAll("\n");
    }
}

fn printMetric(writer: anytype, style: Style, label: []const u8, value: usize) !void {
    try writer.writeAll("  ");
    try style.write(writer, ansi.label, label);
    try writer.writeAll(": ");
    var value_buf: [64]u8 = undefined;
    const formatted = try number_format.formatGroupedUsize(&value_buf, value);
    try style.write(writer, ansi.value, formatted);
    try writer.writeAll("\n");
}

fn printAverageMetric(writer: anytype, style: Style, label: []const u8, total: usize, count: usize) !void {
    const tenths = decimalTenths(total, count);
    const whole = tenths / 10;
    const frac = tenths % 10;
    var whole_buf: [64]u8 = undefined;
    const whole_formatted = try number_format.formatGroupedUsize(&whole_buf, whole);
    try writer.writeAll("  ");
    try style.write(writer, ansi.label, label);
    try writer.writeAll(": ");
    try style.print(writer, ansi.value, "{s}.{d}", .{ whole_formatted, frac });
    try writer.writeAll("\n");
}

fn printTypeTable(
    writer: anytype,
    style: Style,
    rows: []const TypeRow,
) !void {
    var rank_width: usize = 1;
    var ext_width: usize = 3;
    var files_width: usize = 5;
    var lines_width: usize = 5;
    var bytes_width: usize = 5;

    for (rows) |row| {
        rank_width = @max(rank_width, if (row.rank == 0) 1 else number_format.digitCount(row.rank));
        ext_width = @max(ext_width, row.ext.len);

        var files_buf: [64]u8 = undefined;
        var lines_buf: [64]u8 = undefined;
        var bytes_buf: [64]u8 = undefined;
        files_width = @max(files_width, (try number_format.formatGroupedUsize(&files_buf, row.files)).len);
        lines_width = @max(lines_width, (try number_format.formatGroupedUsize(&lines_buf, row.lines)).len);
        bytes_width = @max(bytes_width, (try number_format.formatGroupedUsize(&bytes_buf, row.bytes)).len);
    }

    try writer.writeAll("  | ");
    try style.write(writer, ansi.label, "#");
    try writePadding(writer, rank_width - 1);
    try writer.writeAll(" | ");
    try style.write(writer, ansi.label, "ext");
    try writePadding(writer, ext_width - 3);
    try writer.writeAll(" | ");
    try style.write(writer, ansi.label, "files");
    try writePadding(writer, files_width - 5);
    try writer.writeAll(" | ");
    try style.write(writer, ansi.label, "lines");
    try writePadding(writer, lines_width - 5);
    try writer.writeAll(" | ");
    try style.write(writer, ansi.label, "bytes");
    try writePadding(writer, bytes_width - 5);
    try writer.writeAll(" |\n");

    try writer.writeAll("  |-");
    try writeRepeated(writer, "-", rank_width);
    try writer.writeAll("-|-");
    try writeRepeated(writer, "-", ext_width);
    try writer.writeAll("-|-");
    try writeRepeated(writer, "-", files_width);
    try writer.writeAll("-|-");
    try writeRepeated(writer, "-", lines_width);
    try writer.writeAll("-|-");
    try writeRepeated(writer, "-", bytes_width);
    try writer.writeAll("-|\n");

    for (rows) |row| {
        var files_buf: [64]u8 = undefined;
        var lines_buf: [64]u8 = undefined;
        var bytes_buf: [64]u8 = undefined;
        const files = try number_format.formatGroupedUsize(&files_buf, row.files);
        const lines = try number_format.formatGroupedUsize(&lines_buf, row.lines);
        const bytes = try number_format.formatGroupedUsize(&bytes_buf, row.bytes);

        try writer.writeAll("  | ");
        if (row.rank == 0) {
            try style.write(writer, ansi.label, "*");
            try writePadding(writer, rank_width - 1);
        } else {
            var rank_buf: [16]u8 = undefined;
            const rank_text = try std.fmt.bufPrint(&rank_buf, "{d}", .{row.rank});
            try style.write(writer, ansi.label, rank_text);
            try writePadding(writer, rank_width - rank_text.len);
        }

        try writer.writeAll(" | ");
        try style.write(writer, ansi.ext, row.ext);
        try writePadding(writer, ext_width - row.ext.len);

        try writer.writeAll(" | ");
        try style.write(writer, ansi.value, files);
        try writePadding(writer, files_width - files.len);

        try writer.writeAll(" | ");
        try style.write(writer, ansi.value, lines);
        try writePadding(writer, lines_width - lines.len);

        try writer.writeAll(" | ");
        try style.write(writer, ansi.value, bytes);
        try writePadding(writer, bytes_width - bytes.len);
        try writer.writeAll(" |\n");
    }
}

fn decimalTenths(total: usize, count: usize) usize {
    if (count == 0) return 0;
    const numerator = @as(u128, total) * 10 + @divTrunc(@as(u128, count), 2);
    return @intCast(@divTrunc(numerator, count));
}

fn writePadding(writer: anytype, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeAll(" ");
    }
}

fn writeRepeated(writer: anytype, token: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try writer.writeAll(token);
    }
}

fn extRowLessThan(_: void, left: ExtRow, right: ExtRow) bool {
    if (left.stat.count != right.stat.count) return left.stat.count > right.stat.count;
    if (left.stat.total_lines != right.stat.total_lines) return left.stat.total_lines > right.stat.total_lines;
    return std.mem.order(u8, left.ext, right.ext) == .lt;
}

test "print stats includes skipped section" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    const stats = @import("../stats/ext_stats_update.zig");
    try stats.updateExtensionStats(allocator, &result, ".zig", 10, 100);
    result.total_files = 1;
    result.total_lines = 10;
    result.total_bytes = 100;
    result.skipped.gitignore = 2;

    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printStats(fbs.writer(), &result, .{ .style = .{ .use_color = false } });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SKIPPED") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "gitignore") != null);
}

test "print stats shows none when skipped is empty" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    const stats = @import("../stats/ext_stats_update.zig");
    try stats.updateExtensionStats(allocator, &result, ".zig", 1, 1);
    result.total_files = 1;
    result.total_lines = 1;
    result.total_bytes = 1;

    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStats(fbs.writer(), &result, .{ .style = .{ .use_color = false } });

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "SKIPPED") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "none") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "gitignore: 0") == null);
}
