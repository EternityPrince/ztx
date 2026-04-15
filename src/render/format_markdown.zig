const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const RenderContext = @import("context.zig").RenderContext;
const printTree = @import("render_tree.zig").printTree;
const printContent = @import("render_content.zig").printContent;
const shared = @import("shared.zig");

pub fn printMarkdown(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    try writer.writeAll("# ztx report\n\n");

    if (config.show_stats) {
        try writer.writeAll("## Summary\n");
        try writer.print("- Files: {d}\n", .{result.total_files});
        try writer.print("- Dirs: {d}\n", .{result.total_dirs});
        try writer.print("- Lines: {d}\n", .{result.total_lines});
        try writer.print("- Bytes: {d}\n", .{result.total_bytes});
        try writer.writeAll("\n");

        var rows = try shared.collectSortedExtRows(allocator, result);
        defer rows.deinit(allocator);

        try writer.writeAll("## File Types\n");
        try writer.writeAll("| Ext | Files | Lines | Bytes |\n");
        try writer.writeAll("| --- | ---: | ---: | ---: |\n");

        for (rows.items) |row| {
            try writer.print("| `{s}` | {d} | {d} | {d} |\n", .{
                row.ext,
                row.stat.count,
                row.stat.total_lines,
                row.stat.total_bytes,
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

        var files = try shared.collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
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
