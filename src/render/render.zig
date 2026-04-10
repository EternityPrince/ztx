const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const printStats = @import("../render/render_stats.zig").printStats;
const printTree = @import("render_tree.zig").printTree;
const printContent = @import("render_content.zig").printContent;

// pub fn printOutput(writer: anytype, result: *const model.ScanResult, options: cli.Options) !void {}

pub fn printStdout(writer: anytype, result: *const model.ScanResult, config: cli.Config) !void {
    var need_gap = false;

    if (config.show_stats) {
        try printStats(writer, result);
        need_gap = true;
    }

    if (config.show_tree) {
        if (need_gap) try writer.writeAll("\n");
        try printTree(writer, result);
        need_gap = true;
    }

    if (config.show_content) {
        if (need_gap) try writer.writeAll("\n");
        try printContent(writer, result);
    }
}
