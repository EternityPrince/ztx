const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const RenderContext = @import("context.zig").RenderContext;
const Style = @import("style.zig").Style;
const printStats = @import("render_stats.zig").printStats;
const printTree = @import("render_tree.zig").printTree;
const buildTreeNodes = @import("render_tree.zig").buildTreeNodes;
const kindLabel = @import("render_tree.zig").kindLabel;
const printContent = @import("render_content.zig").printContent;

const FilePtr = *const model.FileInfo;

const ExtRow = struct {
    ext: []const u8,
    stat: model.ExtensionStat,
};

pub fn printStdout(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    switch (config.output_format) {
        .text => try printText(writer, allocator, result, config),
        .markdown => try printMarkdown(writer, allocator, result, config),
        .json => {
            if (config.strict_json) {
                var json_buffer = std.ArrayList(u8).empty;
                defer json_buffer.deinit(allocator);

                try printJson(json_buffer.writer(allocator), allocator, result, config);
                try validateJsonOutput(allocator, json_buffer.items);
                try writer.writeAll(json_buffer.items);
            } else {
                try printJson(writer, allocator, result, config);
            }
        },
    }
}

fn printText(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    const context = RenderContext{
        .style = Style{ .use_color = config.use_color },
    };

    var files = try collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
    defer files.deinit(allocator);

    var need_gap = false;

    if (config.show_stats) {
        try printStats(writer, result, context);
        need_gap = true;
    }

    if (config.show_tree) {
        if (need_gap and !config.compact) try writer.writeAll("\n");
        try printTree(writer, allocator, result, context, config.tree_sort_mode);
        need_gap = true;
    }

    if (config.show_content) {
        if (need_gap and !config.compact) try writer.writeAll("\n");
        try printContent(writer, files.items, context, config.compact);
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
        var has_skipped = false;
        if (result.skipped.gitignore > 0) {
            try writer.print("- gitignore: {d}\n", .{result.skipped.gitignore});
            has_skipped = true;
        }
        if (result.skipped.builtin > 0) {
            try writer.print("- builtin: {d}\n", .{result.skipped.builtin});
            has_skipped = true;
        }
        if (result.skipped.binary_or_unsupported > 0) {
            try writer.print("- binary/unsupported: {d}\n", .{result.skipped.binary_or_unsupported});
            has_skipped = true;
        }
        if (result.skipped.size_limit > 0) {
            try writer.print("- size limit: {d}\n", .{result.skipped.size_limit});
            has_skipped = true;
        }
        if (result.skipped.content_policy > 0) {
            try writer.print("- content policy: {d}\n", .{result.skipped.content_policy});
            has_skipped = true;
        }
        if (result.skipped.depth_limit > 0) {
            try writer.print("- depth limit: {d}\n", .{result.skipped.depth_limit});
            has_skipped = true;
        }
        if (result.skipped.file_limit > 0) {
            try writer.print("- file limit: {d}\n", .{result.skipped.file_limit});
            has_skipped = true;
        }
        if (result.skipped.symlink > 0) {
            try writer.print("- symlink: {d}\n", .{result.skipped.symlink});
            has_skipped = true;
        }
        if (result.skipped.permission > 0) {
            try writer.print("- permission: {d}\n", .{result.skipped.permission});
            has_skipped = true;
        }
        if (!has_skipped) {
            try writer.writeAll("- none\n");
        }
        try writer.writeAll("\n");
    }

    if (config.show_tree) {
        var tree_buf = std.ArrayList(u8).empty;
        defer tree_buf.deinit(allocator);

        const tree_context = RenderContext{ .style = .{ .use_color = false } };
        try printTree(tree_buf.writer(allocator), allocator, result, tree_context, config.tree_sort_mode);

        try writer.writeAll("## Directory Tree\n```text\n");
        try writer.writeAll(tree_buf.items);
        try writer.writeAll("```\n\n");
    }

    if (config.show_content) {
        var content_buf = std.ArrayList(u8).empty;
        defer content_buf.deinit(allocator);

        var files = try collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
        defer files.deinit(allocator);

        const content_context = RenderContext{ .style = .{ .use_color = false } };
        try printContent(content_buf.writer(allocator), files.items, content_context, config.compact);

        if (content_buf.items.len > 0) {
            try writer.writeAll("## Files\n```text\n");
            try writer.writeAll(content_buf.items);
            try writer.writeAll("```\n");
        }
    }
}

fn printJson(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    var files = try collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
    defer files.deinit(allocator);

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

    var tree_nodes = try buildTreeNodes(allocator, result);
    defer tree_nodes.deinit(allocator);

    try writer.writeAll("\"tree\":[");
    for (tree_nodes.items, 0..) |node, idx| {
        if (idx > 0) try writer.writeAll(",");
        try writer.writeAll("{\"path\":");
        try writeJsonString(writer, node.path);
        try writer.print(
            ",\"kind\":\"{s}\",\"depth\":{d},\"files\":{d},\"lines\":{d},\"comments\":{d},\"bytes\":{d}}}",
            .{
                kindLabel(node.kind),
                node.depth,
                node.file_count,
                node.line_count,
                node.comment_line_count,
                node.byte_size,
            },
        );
    }
    try writer.writeAll("],");

    try writer.writeAll("\"files\":[");
    for (files.items, 0..) |file, idx| {
        if (idx > 0) try writer.writeAll(",");

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
    }
    try writer.writeAll("],");

    try writer.writeAll("\"skipped\":{");
    try writer.print(
        "\"gitignore\":{d},\"builtin\":{d},\"binary\":{d},\"size_limit\":{d},\"content_policy\":{d},\"depth_limit\":{d},\"file_limit\":{d},\"symlink\":{d},\"permission\":{d}",
        .{
            result.skipped.gitignore,
            result.skipped.builtin,
            result.skipped.binary_or_unsupported,
            result.skipped.size_limit,
            result.skipped.content_policy,
            result.skipped.depth_limit,
            result.skipped.file_limit,
            result.skipped.symlink,
            result.skipped.permission,
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

fn collectSortedFiles(
    allocator: std.mem.Allocator,
    result: *const model.ScanResult,
    sort_mode: cli.SortMode,
    top_files: ?usize,
) !std.ArrayList(FilePtr) {
    var files = std.ArrayList(FilePtr).empty;
    errdefer files.deinit(allocator);

    for (result.entries.items) |*entry| {
        switch (entry.*) {
            .file => |*file| try files.append(allocator, file),
            .dir => {},
        }
    }

    switch (sort_mode) {
        .name => std.mem.sort(FilePtr, files.items, {}, fileLessByName),
        .size => std.mem.sort(FilePtr, files.items, {}, fileLessBySize),
        .lines => std.mem.sort(FilePtr, files.items, {}, fileLessByLines),
    }

    if (top_files) |limit| {
        if (limit < files.items.len) {
            files.shrinkAndFree(allocator, limit);
        }
    }

    return files;
}

fn fileLessByName(_: void, left: FilePtr, right: FilePtr) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn fileLessBySize(_: void, left: FilePtr, right: FilePtr) bool {
    if (left.byte_size != right.byte_size) return left.byte_size > right.byte_size;
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn fileLessByLines(_: void, left: FilePtr, right: FilePtr) bool {
    if (left.line_count != right.line_count) return left.line_count > right.line_count;
    return std.mem.order(u8, left.path, right.path) == .lt;
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
    try writer.print("{f}", .{std.json.fmt(value, .{})});
}

fn validateJsonOutput(allocator: std.mem.Allocator, output: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, output, .{}) catch {
        return error.InvalidJsonOutput;
    };
    defer parsed.deinit();

    const root = try expectObject(parsed.value);

    const summary = try expectFieldObject(root, "summary");
    try expectNumberField(summary, "files");
    try expectNumberField(summary, "dirs");
    try expectNumberField(summary, "lines");
    try expectNumberField(summary, "bytes");

    const types = try expectFieldArray(root, "types");
    for (types.items) |type_entry| {
        const type_obj = try expectObject(type_entry);
        _ = try expectFieldString(type_obj, "ext");
        try expectNumberField(type_obj, "files");
        try expectNumberField(type_obj, "lines");
        try expectNumberField(type_obj, "bytes");
        try expectNumberField(type_obj, "share_files");
        try expectNumberField(type_obj, "share_lines");
        try expectNumberField(type_obj, "share_bytes");
    }

    const tree = try expectFieldArray(root, "tree");
    for (tree.items) |tree_entry| {
        const tree_obj = try expectObject(tree_entry);
        _ = try expectFieldString(tree_obj, "path");
        const kind = try expectFieldString(tree_obj, "kind");
        if (!std.mem.eql(u8, kind, "dir") and !std.mem.eql(u8, kind, "file")) {
            return error.InvalidJsonOutput;
        }
        try expectNumberField(tree_obj, "depth");
        try expectNumberField(tree_obj, "files");
        try expectNumberField(tree_obj, "lines");
        try expectNumberField(tree_obj, "comments");
        try expectNumberField(tree_obj, "bytes");
    }

    const files = try expectFieldArray(root, "files");
    for (files.items) |file_entry| {
        const file_obj = try expectObject(file_entry);
        _ = try expectFieldString(file_obj, "path");
        try expectNumberField(file_obj, "line_count");
        try expectNumberField(file_obj, "byte_size");

        if (file_obj.get("content")) |content| {
            switch (content) {
                .null, .string => {},
                else => return error.InvalidJsonOutput,
            }
        }
    }

    const skipped = try expectFieldObject(root, "skipped");
    const skipped_keys = [_][]const u8{
        "gitignore",
        "builtin",
        "binary",
        "size_limit",
        "content_policy",
        "depth_limit",
        "file_limit",
        "symlink",
        "permission",
    };
    for (skipped_keys) |key| {
        try expectNumberField(skipped, key);
    }
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    if (value != .object) return error.InvalidJsonOutput;
    return value.object;
}

fn expectArray(value: std.json.Value) !std.json.Array {
    if (value != .array) return error.InvalidJsonOutput;
    return value.array;
}

fn expectField(obj: std.json.ObjectMap, key: []const u8) !std.json.Value {
    return obj.get(key) orelse return error.InvalidJsonOutput;
}

fn expectFieldObject(obj: std.json.ObjectMap, key: []const u8) !std.json.ObjectMap {
    return expectObject(try expectField(obj, key));
}

fn expectFieldArray(obj: std.json.ObjectMap, key: []const u8) !std.json.Array {
    return expectArray(try expectField(obj, key));
}

fn expectFieldString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = try expectField(obj, key);
    if (value != .string) return error.InvalidJsonOutput;
    return value.string;
}

fn expectNumberField(obj: std.json.ObjectMap, key: []const u8) !void {
    try expectNumber(try expectField(obj, key));
}

fn expectNumber(value: std.json.Value) !void {
    switch (value) {
        .integer, .float, .number_string => {},
        else => return error.InvalidJsonOutput,
    }
}

fn makeTestConfig(allocator: std.mem.Allocator, format: cli.OutputFormat) !cli.Config {
    var config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = format,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .changed_base = null,
        .include_patterns = std.ArrayList([]const u8).empty,
        .exclude_patterns = std.ArrayList([]const u8).empty,
        .strict_json = false,
        .compact = false,
        .sort_mode = .name,
        .tree_sort_mode = .name,
        .content_preset = .balanced,
        .content_exclude_patterns = std.ArrayList([]const u8).empty,
        .top_files = null,
        .profile_name = null,
    };
    try config.paths.append(allocator, try allocator.dupe(u8, "."));
    return config;
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
        .comment_line_count = 0,
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

    var config = try makeTestConfig(allocator, .text);
    defer config.deinit(allocator);
    config.show_tree = false;
    config.show_stats = false;

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

    var config = try makeTestConfig(allocator, .json);
    defer config.deinit(allocator);

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

test "json strict mode validates output schema" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = try makeTestConfig(allocator, .json);
    defer config.deinit(allocator);
    config.strict_json = true;

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, fbs.getWritten(), .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("summary") != null);
}

test "json schema validation rejects missing required fields" {
    const allocator = std.testing.allocator;
    const missing_permission =
        \\{"summary":{"files":1,"dirs":1,"lines":1,"bytes":1},"types":[],"tree":[],"files":[],"skipped":{"gitignore":0,"builtin":0,"binary":0,"size_limit":0,"depth_limit":0,"file_limit":0,"symlink":0}}
    ;
    try std.testing.expectError(error.InvalidJsonOutput, validateJsonOutput(allocator, missing_permission));
}

test "json schema validation rejects wrong field types" {
    const allocator = std.testing.allocator;
    const wrong_types =
        \\{"summary":{"files":"1","dirs":1,"lines":1,"bytes":1},"types":[],"tree":[],"files":[],"skipped":{"gitignore":0,"builtin":0,"binary":0,"size_limit":0,"depth_limit":0,"file_limit":0,"symlink":0,"permission":0}}
    ;
    try std.testing.expectError(error.InvalidJsonOutput, validateJsonOutput(allocator, wrong_types));
}

test "json schema validation rejects invalid file content type" {
    const allocator = std.testing.allocator;
    const invalid_file_content =
        \\{"summary":{"files":1,"dirs":1,"lines":1,"bytes":1},"types":[],"tree":[],"files":[{"path":"a.zig","line_count":1,"byte_size":1,"content":1}],"skipped":{"gitignore":0,"builtin":0,"binary":0,"size_limit":0,"depth_limit":0,"file_limit":0,"symlink":0,"permission":0}}
    ;
    try std.testing.expectError(error.InvalidJsonOutput, validateJsonOutput(allocator, invalid_file_content));
}

test "json files respect sort and top-files" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    try result.entries.append(allocator, .{ .file = .{
        .path = try allocator.dupe(u8, "a.zig"),
        .extension = try allocator.dupe(u8, ".zig"),
        .line_count = 5,
        .comment_line_count = 0,
        .byte_size = 10,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = try allocator.dupe(u8, "b.zig"),
        .extension = try allocator.dupe(u8, ".zig"),
        .line_count = 10,
        .comment_line_count = 0,
        .byte_size = 50,
        .depth_level = 0,
        .content = null,
    } });
    result.total_files = 2;

    var config = try makeTestConfig(allocator, .json);
    defer config.deinit(allocator);
    config.show_content = false;
    config.sort_mode = .size;
    config.top_files = 1;

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\"path\":\"b.zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"path\":\"a.zig\"") == null);
}

test "golden text output for default flow" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = try makeTestConfig(allocator, .text);
    defer config.deinit(allocator);

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
        \\  none
        \\
        \\DIRECTORY TREE
        \\└── src/  [F:1 L:1 C:0 B:13B]
        \\    └── main.zig  [L:1 C:0 B:13B]
        \\
        \\FILES
        \\===== src/main.zig =====
        \\1 │ const x = 1;
        \\
    ;
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "golden text output for stats profile flow" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = try makeTestConfig(allocator, .text);
    defer config.deinit(allocator);
    config.show_tree = false;
    config.show_content = false;

    var buffer: [8192]u8 = undefined;
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
        \\  none
        \\
    ;
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "golden markdown output for llm flow" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var config = try makeTestConfig(allocator, .markdown);
    defer config.deinit(allocator);

    var buffer: [32768]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const expected =
        \\# ztx report
        \\
        \\## Summary
        \\- Files: 1
        \\- Dirs: 1
        \\- Lines: 1
        \\- Bytes: 13
        \\
        \\## File Types
        \\| Ext | Files | Lines | Bytes | Share Files | Share Lines | Share Bytes |
        \\| --- | ---: | ---: | ---: | ---: | ---: | ---: |
        \\| `.zig` | 1 | 1 | 13 | 100.0% | 100.0% | 100.0% |
        \\
        \\## Skipped
        \\- none
        \\
        \\## Directory Tree
        \\```text
        \\DIRECTORY TREE
        \\└── src/  [F:1 L:1 C:0 B:13B]
        \\    └── main.zig  [L:1 C:0 B:13B]
        \\```
        \\
        \\## Files
        \\```text
        \\FILES
        \\===== src/main.zig =====
        \\1 │ const x = 1;
        \\
        \\```
    ;
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}
