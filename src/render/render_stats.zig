const std = @import("std");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;

const ExtRow = struct {
    ext: []const u8,
    stat: model.ExtensionStat,
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

    for (rows.items[0..shown], 0..) |row, idx| {
        shown_files += row.stat.count;
        shown_lines += row.stat.total_lines;
        shown_bytes += row.stat.total_bytes;
        try printExtRow(writer, style, idx + 1, row.ext, row.stat, result.total_files, result.total_lines, result.total_bytes);
    }

    if (rows.items.len > top_types_limit) {
        const others = model.ExtensionStat{
            .count = result.total_files - shown_files,
            .total_lines = result.total_lines - shown_lines,
            .total_bytes = result.total_bytes - shown_bytes,
        };

        try printExtRow(writer, style, 0, "others", others, result.total_files, result.total_lines, result.total_bytes);
    }

    try writer.writeAll("\n");
    try style.write(writer, ansi.section, "SKIPPED\n");
    try printMetric(writer, style, "gitignore", result.skipped.gitignore);
    try printMetric(writer, style, "builtin", result.skipped.builtin);
    try printMetric(writer, style, "binary/unsupported", result.skipped.binary_or_unsupported);
    try printMetric(writer, style, "size limit", result.skipped.size_limit);
    try printMetric(writer, style, "depth limit", result.skipped.depth_limit);
    try printMetric(writer, style, "file limit", result.skipped.file_limit);
    try printMetric(writer, style, "symlink", result.skipped.symlink);
    try printMetric(writer, style, "permission", result.skipped.permission);
}

fn printMetric(writer: anytype, style: Style, label: []const u8, value: usize) !void {
    try writer.writeAll("  ");
    try style.write(writer, ansi.label, label);
    try writer.writeAll(": ");
    try style.print(writer, ansi.value, "{d}", .{value});
    try writer.writeAll("\n");
}

fn printAverageMetric(writer: anytype, style: Style, label: []const u8, total: usize, count: usize) !void {
    const tenths = decimalTenths(total, count);
    try writer.writeAll("  ");
    try style.write(writer, ansi.label, label);
    try writer.writeAll(": ");
    try style.print(writer, ansi.value, "{d}.{d}", .{ tenths / 10, tenths % 10 });
    try writer.writeAll("\n");
}

fn printExtRow(
    writer: anytype,
    style: Style,
    rank: usize,
    ext: []const u8,
    stat: model.ExtensionStat,
    total_files: usize,
    total_lines: usize,
    total_bytes: usize,
) !void {
    try writer.writeAll("  ");
    if (rank == 0) {
        try style.write(writer, ansi.label, "*");
    } else {
        try style.print(writer, ansi.label, "{d}.", .{rank});
    }
    try writer.writeAll(" ");
    try style.write(writer, ansi.ext, ext);
    try writer.writeAll(" | files: ");
    try style.print(writer, ansi.value, "{d}", .{stat.count});
    try writer.writeAll(" | lines: ");
    try style.print(writer, ansi.value, "{d}", .{stat.total_lines});
    try writer.writeAll(" | bytes: ");
    try style.print(writer, ansi.value, "{d}", .{stat.total_bytes});
    try writer.writeAll(" | share: ");
    try printPercent(writer, style, stat.count, total_files);
    try writer.writeAll(" / ");
    try printPercent(writer, style, stat.total_lines, total_lines);
    try writer.writeAll(" / ");
    try printPercent(writer, style, stat.total_bytes, total_bytes);
    try writer.writeAll("\n");
}

fn printPercent(writer: anytype, style: Style, part: usize, total: usize) !void {
    const scaled = @as(u128, part) * 100;
    const tenths = decimalTenthsFromWide(scaled, total);
    try style.print(writer, ansi.value, "{d}.{d}%", .{ tenths / 10, tenths % 10 });
}

fn decimalTenths(total: usize, count: usize) usize {
    if (count == 0) return 0;
    const numerator = @as(u128, total) * 10 + @divTrunc(@as(u128, count), 2);
    return @intCast(@divTrunc(numerator, count));
}

fn decimalTenthsFromWide(total: u128, count: usize) usize {
    if (count == 0) return 0;
    const numerator = total * 10 + @divTrunc(@as(u128, count), 2);
    return @intCast(@divTrunc(numerator, count));
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
