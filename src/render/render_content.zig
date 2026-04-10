const std = @import("std");
const model = @import("../model.zig");

pub fn printContent(writer: anytype, result: *const model.ScanResult) !void {
    try writer.writeAll("FILES\n");

    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => {},
            .file => |file| {
                try writer.print("===== {s} =====\n", .{file.path});

                if (file.content) |content| {
                    try writer.writeAll(content);
                }

                try writer.writeAll("\n");
            },
        }
    }
}
