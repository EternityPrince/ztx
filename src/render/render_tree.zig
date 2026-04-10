const std = @import("std");
const model = @import("../model.zig");
const printIndent = @import("../helper/render_helper.zig").printIndent;
const baseName = @import("../helper/render_helper.zig").baseName;

pub fn printTree(writer: anytype, result: *const model.ScanResult) !void {
    try writer.writeAll("DIRECTORY TREE\n");

    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => |dir| {
                try printIndent(writer, dir.depth_level);
                try writer.print("{s}/\n", .{baseName(dir.path)});
            },
            .file => |file| {
                try printIndent(writer, file.depth_level);
                try writer.print("{s}\n", .{baseName(file.path)});
            },
        }
    }
}
