const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const RenderContext = @import("context.zig").RenderContext;
const Style = @import("style.zig").Style;
const printStats = @import("../render/render_stats.zig").printStats;
const printTree = @import("render_tree.zig").printTree;
const printContent = @import("render_content.zig").printContent;

// pub fn printOutput(writer: anytype, result: *const model.ScanResult, options: cli.Options) !void {}

pub fn printStdout(writer: anytype, result: *const model.ScanResult, config: cli.Config) !void {
    const context = RenderContext{
        .style = Style{
            .use_color = config.use_color,
        },
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

fn makeTestResult(allocator: std.mem.Allocator) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    const dir_path = try allocator.dupe(u8, "src");
    const file_path = try allocator.dupe(u8, "src/main.zig");
    const ext = try allocator.dupe(u8, ".zig");
    const content = try allocator.dupe(u8, "const x = 1;\n");

    try result.entries.append(allocator, .{
        .dir = .{
            .path = dir_path,
            .depth_level = 0,
        },
    });
    try result.entries.append(allocator, .{
        .file = .{
            .path = file_path,
            .extansion = ext,
            .line_count = 1,
            .byte_size = content.len,
            .depth_level = 1,
            .content = content,
        },
    });

    result.total_dirs = 1;
    result.total_files = 1;
    result.total_lines = 1;
    result.total_bytes = content.len;

    const stats = @import("../stats/ext_stats_update.zig");
    try stats.updateExtansionStats(allocator, &result, ".zig", 1, content.len);
    return result;
}

test "printStdout respects section flags" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    const config = cli.Config{
        .show_content = true,
        .show_tree = false,
        .show_help = false,
        .show_stats = false,
        .use_color = false,
        .scan_mode = .default,
    };

    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), &result, config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "FILES") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "SUMMARY") == null);
}

test "printStdout emits no ANSI codes when color disabled" {
    const allocator = std.testing.allocator;
    var result = try makeTestResult(allocator);
    defer result.deinit(allocator);

    const config = cli.Config{
        .show_content = true,
        .show_tree = true,
        .show_help = false,
        .show_stats = true,
        .use_color = false,
        .scan_mode = .default,
    };

    var buffer: [16384]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printStdout(fbs.writer(), &result, config);

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[") == null);
}
