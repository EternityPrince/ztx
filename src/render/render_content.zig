const std = @import("std");
const model = @import("../model.zig");
const printFileBody = @import("../helper/render_helper.zig").printFileBody;

pub fn printContent(writer: anytype, result: *const model.ScanResult) !void {
    try writer.writeAll("FILES\n");

    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => {},
            .file => |file| {
                try writer.print("===== {s} =====\n", .{file.path});
                try printFileBody(writer, file.path);
                try writer.writeAll("\n");
            },
        }
    }
}
