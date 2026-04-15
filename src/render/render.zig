const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const parse = @import("../cli/parse.zig");
const format_text = @import("format_text.zig");
const format_markdown = @import("format_markdown.zig");
const format_json = @import("format_json.zig");

pub fn printStdout(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    switch (config.output_format) {
        .text => try format_text.printText(writer, allocator, result, config),
        .markdown => try format_markdown.printMarkdown(writer, allocator, result, config),
        .json => {
            if (config.strict_json) {
                var json_buffer = std.ArrayList(u8).empty;
                defer json_buffer.deinit(allocator);

                try format_json.printJson(json_buffer.writer(allocator), allocator, result, config);
                try format_json.validateJsonOutput(allocator, json_buffer.items);
                try writer.writeAll(json_buffer.items);
            } else {
                try format_json.printJson(writer, allocator, result, config);
            }
        },
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

test "default run configuration renders tree only in text format" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    var options = parse.RunOptions{};
    defer options.deinit(allocator);
    var config = try cli.Config.fromRunOptions(allocator, options);
    defer config.deinit(allocator);

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), allocator, &result, &config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") == null);
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
    try std.testing.expectError(error.InvalidJsonOutput, format_json.validateJsonOutput(allocator, missing_permission));
}

test "json schema validation rejects wrong field types" {
    const allocator = std.testing.allocator;
    const wrong_types =
        \\{"summary":{"files":"1","dirs":1,"lines":1,"bytes":1},"types":[],"tree":[],"files":[],"skipped":{"gitignore":0,"builtin":0,"binary":0,"size_limit":0,"depth_limit":0,"file_limit":0,"symlink":0,"permission":0}}
    ;
    try std.testing.expectError(error.InvalidJsonOutput, format_json.validateJsonOutput(allocator, wrong_types));
}

test "json schema validation rejects invalid file content type" {
    const allocator = std.testing.allocator;
    const invalid_file_content =
        \\{"summary":{"files":1,"dirs":1,"lines":1,"bytes":1},"types":[],"tree":[],"files":[{"path":"a.zig","line_count":1,"byte_size":1,"content":1}],"skipped":{"gitignore":0,"builtin":0,"binary":0,"size_limit":0,"depth_limit":0,"file_limit":0,"symlink":0,"permission":0}}
    ;
    try std.testing.expectError(error.InvalidJsonOutput, format_json.validateJsonOutput(allocator, invalid_file_content));
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

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILE TYPES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "| # | ext") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SKIPPED") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "none") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── src/") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "· F:1 · L:1 · C:0 · B:13B") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "· L:1 · C:0 · B:13B") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "===== src/main.zig =====") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 │ const x = 1;") != null);
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

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILE TYPES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "| # | ext") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SKIPPED") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "none") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") == null);
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

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "# ztx report") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## File Types") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "| `.zig` | 1 | 1 | 13 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Skipped") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "- none") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Directory Tree") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── src/") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "· F:1 · L:1 · C:0 · B:13B") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── main.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "· L:1 · C:0 · B:13B") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "## Files") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "===== src/main.zig =====") != null);
}
