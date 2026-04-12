const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const RenderContext = @import("context.zig").RenderContext;
const Style = @import("style.zig").Style;
const printStats = @import("render_stats.zig").printStats;
const printTree = @import("render_tree.zig").printTree;
const printContent = @import("render_content.zig").printContent;

const ExtRow = struct {
    ext: []const u8,
    stat: model.ExtensionStat,
};

pub fn printStdout(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    switch (config.output_format) {
        .text => try printText(writer, result, config),
        .markdown => try printMarkdown(writer, allocator, result, config),
        .json => try printJson(writer, allocator, result, config),
    }
}

fn printText(writer: anytype, result: *const model.ScanResult, config: *const cli.Config) !void {
    const context = RenderContext{
        .style = Style{ .use_color = config.use_color },
    };

    var need_gap = false;

    if (config.show_stats) {
        try printStats(writer, result, context);
        need_gap = true;
    }

    if (config.show_tree) {
        if (need_gap) try writer.writeAll("\n");
        try printTree(writer, result, context);
        need_gap = true;
    }

    if (config.show_content) {
        if (need_gap) try writer.writeAll("\n");
        try printContent(writer, result, context);
    }
}

fn printMarkdown(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    try writer.writeAll("# ztx report\n\n");

    if (config.show_stats) {
        try writer.writeAll("## Summary\n");
        try writer.print("- Files: {d}\n", .{result.total_files});
        try writer.print("- Dirs: {d}\n", .{result.total_dirs});
        try writer.print("- Lines: {d}\n", .{result.total_lines});
        try writer.print("- Bytes: {d}\n", .{result.total_bytes});
        try writer.writeAll("\n");

        var rows = try collectSortedExtRows(allocator, result);
        defer rows.deinit(allocator);

        try writer.writeAll("## File Types\n");
        try writer.writeAll("| Ext | Files | Lines | Bytes | Share Files | Share Lines | Share Bytes |\n");
        try writer.writeAll("| --- | ---: | ---: | ---: | ---: | ---: | ---: |\n");

        for (rows.items) |row| {
            try writer.print("| `{s}` | {d} | {d} | {d} | {d:.1}% | {d:.1}% | {d:.1}% |\n", .{
                row.ext,
                row.stat.count,
                row.stat.total_lines,
                row.stat.total_bytes,
                sharePercent(row.stat.count, result.total_files),
                sharePercent(row.stat.total_lines, result.total_lines),
                sharePercent(row.stat.total_bytes, result.total_bytes),
            });
        }

        try writer.writeAll("\n## Skipped\n");
        try writer.print("- gitignore: {d}\n", .{result.skipped.gitignore});
        try writer.print("- builtin: {d}\n", .{result.skipped.builtin});
        try writer.print("- binary/unsupported: {d}\n", .{result.skipped.binary_or_unsupported});
        try writer.print("- size limit: {d}\n", .{result.skipped.size_limit});
        try writer.print("- depth limit: {d}\n", .{result.skipped.depth_limit});
        try writer.print("- file limit: {d}\n", .{result.skipped.file_limit});
        try writer.writeAll("\n");
    }

    if (config.show_tree) {
        var tree_buf = std.ArrayList(u8).empty;
        defer tree_buf.deinit(allocator);

        const tree_context = RenderContext{ .style = .{ .use_color = false } };
        try printTree(tree_buf.writer(allocator), result, tree_context);

        try writer.writeAll("## Directory Tree\n```text\n");
        try writer.writeAll(tree_buf.items);
        try writer.writeAll("```\n\n");
    }

    if (config.show_content) {
        var content_buf = std.ArrayList(u8).empty;
        defer content_buf.deinit(allocator);

        const content_context = RenderContext{ .style = .{ .use_color = false } };
        try printContent(content_buf.writer(allocator), result, content_context);

        try writer.writeAll("## Files\n```text\n");
        try writer.writeAll(content_buf.items);
        try writer.writeAll("```\n");
    }
}

fn printJson(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    try writer.writeAll("{");

    try writer.writeAll("\"summary\":{");
    try writer.print("\"files\":{d},\"dirs\":{d},\"lines\":{d},\"bytes\":{d}", .{
        result.total_files,
        result.total_dirs,
        result.total_lines,
        result.total_bytes,
    });
    try writer.writeAll("},");

    var rows = try collectSortedExtRows(allocator, result);
    defer rows.deinit(allocator);

    try writer.writeAll("\"types\":[");
    for (rows.items, 0..) |row, idx| {
        if (idx > 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writer.writeAll("\"ext\":");
        try writeJsonString(writer, row.ext);
        try writer.writeAll(",");
        try writer.print("\"files\":{d},\"lines\":{d},\"bytes\":{d},", .{ row.stat.count, row.stat.total_lines, row.stat.total_bytes });
        try writer.print("\"share_files\":{d:.1},\"share_lines\":{d:.1},\"share_bytes\":{d:.1}", .{
            sharePercent(row.stat.count, result.total_files),
            sharePercent(row.stat.total_lines, result.total_lines),
            sharePercent(row.stat.total_bytes, result.total_bytes),
        });
        try writer.writeAll("}");
    }
    try writer.writeAll("],");

    try writer.writeAll("\"tree\":[");
    var first_tree = true;
    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => |dir| {
                if (!first_tree) try writer.writeAll(",");
                first_tree = false;
                try writer.writeAll("{\"path\":");
                try writeJsonString(writer, dir.path);
                try writer.print(",\"kind\":\"dir\",\"depth\":{d}}}", .{dir.depth_level});
            },
            .file => |file| {
                if (!first_tree) try writer.writeAll(",");
                first_tree = false;
                try writer.writeAll("{\"path\":");
                try writeJsonString(writer, file.path);
                try writer.print(",\"kind\":\"file\",\"depth\":{d}}}", .{file.depth_level});
            },
        }
    }
    try writer.writeAll("],");

    try writer.writeAll("\"files\":[");
    var first_file = true;
    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => {},
            .file => |file| {
                if (!first_file) try writer.writeAll(",");
                first_file = false;

                try writer.writeAll("{\"path\":");
                try writeJsonString(writer, file.path);
                try writer.print(",\"line_count\":{d},\"byte_size\":{d}", .{ file.line_count, file.byte_size });

                if (config.show_content) {
                    try writer.writeAll(",\"content\":");
                    if (file.content) |content| {
                        try writeJsonString(writer, content);
                    } else {
                        try writer.writeAll("null");
                    }
                }

                try writer.writeAll("}");
            },
        }
    }
    try writer.writeAll("],");

    try writer.writeAll("\"skipped\":{");
    try writer.print(
        "\"gitignore\":{d},\"builtin\":{d},\"binary\":{d},\"size_limit\":{d},\"depth_limit\":{d},\"file_limit\":{d}",
        .{
            result.skipped.gitignore,
            result.skipped.builtin,
            result.skipped.binary_or_unsupported,
            result.skipped.size_limit,
            result.skipped.depth_limit,
            result.skipped.file_limit,
        },
    );
    try writer.writeAll("}");

    try writer.writeAll("}\n");
}

fn collectSortedExtRows(allocator: std.mem.Allocator, result: *const model.ScanResult) !std.ArrayList(ExtRow) {
    var rows = std.ArrayList(ExtRow).empty;
    errdefer rows.deinit(allocator);

    var iterator = result.ext_stats.iterator();
    while (iterator.next()) |entry| {
        try rows.append(allocator, .{ .ext = entry.key_ptr.*, .stat = entry.value_ptr.* });
    }

    std.mem.sort(ExtRow, rows.items, {}, extRowLessThan);
    return rows;
}

fn extRowLessThan(_: void, left: ExtRow, right: ExtRow) bool {
    if (left.stat.count != right.stat.count) return left.stat.count > right.stat.count;
    if (left.stat.total_lines != right.stat.total_lines) return left.stat.total_lines > right.stat.total_lines;
    return std.mem.order(u8, left.ext, right.ext) == .lt;
}

fn sharePercent(part: usize, total: usize) f64 {
    if (total == 0) return 0;
    return @as(f64, @floatFromInt(part)) * 100.0 / @as(f64, @floatFromInt(total));
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn makeTestResult(allocator: std.mem.Allocator) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    const dir_path = try allocator.dupe(u8, "src");
    const file_path = try allocator.dupe(u8, "src/main.zig");
    const ext = try allocator.dupe(u8, ".zig");
    const content = try allocator.dupe(u8, "const x = 1;\n");

    try result.entries.append(allocator, .{ .dir = .{ .path = dir_path, .depth_level = 0 } });
    try result.entries.append(allocator, .{ .file = .{
        .path = file_path,
        .extension = ext,
        .line_count = 1,
        .byte_size = content.len,
        .depth_level = 1,
        .content = content,
    } });

    result.total_dirs = 1;
    result.total_files = 1;
    result.total_lines = 1;
    result.total_bytes = content.len;

    const stats = @import("../stats/ext_stats_update.zig");
    try stats.updateExtensionStats(allocator, &result, ".zig", 1, content.len);

    return result;
}

test "text format respects section flags" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = true,
        .show_tree = false,
        .show_stats = false,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .text,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);

    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") == null);
}

test "json format emits stable top-level keys" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .json,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);

    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"types\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"tree\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"files\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"skipped\"") != null);
}

test "text default snapshot is stable" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .text,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);
    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const expected =
        \\SUMMARY
        \\  Files: 1
        \\  Dirs: 1
        \\  Lines: 1
        \\  Bytes: 13
        \\  Avg lines/file: 1.0
        \\  Avg bytes/file: 13.0
        \\
        \\FILE TYPES (Top 10 by files)
        \\  1. .zig | files: 1 | lines: 1 | bytes: 13 | share: 100.0% / 100.0% / 100.0%
        \\
        \\SKIPPED
        \\  gitignore: 0
        \\  builtin: 0
        \\  binary/unsupported: 0
        \\  size limit: 0
        \\  depth limit: 0
        \\  file limit: 0
        \\
        \\DIRECTORY TREE
        \\└── src/
        \\    └── main.zig
        \\
        \\FILES
        \\===== src/main.zig =====
        \\1 │ const x = 1;
        \\
        \\
    ;

    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "markdown llm snapshot is stable" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .markdown,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);
    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.startsWith(u8, output, "# ztx report\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "## Summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Directory Tree") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Files") != null);
}

test "text stats snapshot is stable" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = false,
        .show_tree = false,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .text,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);
    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILE TYPES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") == null);
}

test "json snapshot is parseable and stable for top-level schema" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .json,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);
    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, fbs.getWritten(), .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expect(object.get("summary") != null);
    try std.testing.expect(object.get("types") != null);
    try std.testing.expect(object.get("tree") != null);
    try std.testing.expect(object.get("files") != null);
    try std.testing.expect(object.get("skipped") != null);
}
