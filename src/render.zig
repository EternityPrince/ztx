const std = @import("std");
const model = @import("model.zig");

pub fn printSummary(writer: anytype, result: *const model.ScanResult) !void {
    try writer.print("Total files: {d}\n", .{result.total_files});
    try writer.print("Total lines: {d}\n", .{result.total_lines});
    try writer.writeAll("\nDetected file types:\n");

    var iterator = result.ext_stats.iterator();
    while (iterator.next()) |ext| {
        try writer.print("  {d} files {s} ({d} lines)\n", .{ ext.value_ptr.count, ext.key_ptr.*, ext.value_ptr.total_lines });
    }

    try writer.writeAll("\nFiles:\n");
    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => |dir| {
                try writer.print("  [dir] {s}\n", .{dir.path});
            },
            .file => |file| {
                try writer.print(
                    "  {s} | ext={s} | lines={d} | bytes={d}\n",
                    .{ file.path, file.extansion, file.line_count, file.byte_size },
                );
            },
        }
    }
}
