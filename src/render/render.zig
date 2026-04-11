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
