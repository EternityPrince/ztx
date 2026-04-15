const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const RenderContext = @import("context.zig").RenderContext;
const Style = @import("style.zig").Style;
const printStats = @import("render_stats.zig").printStats;
const printTree = @import("render_tree.zig").printTree;
const printContent = @import("render_content.zig").printContent;
const shared = @import("shared.zig");

pub fn printText(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    _ = Style;
    const context = RenderContext{
        .style = .{ .use_color = config.use_color },
    };

    var files = try shared.collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
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
