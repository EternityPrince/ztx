const std = @import("std");
const model = @import("../model.zig");

pub fn printStats(writer: anytype, result: *const model.ScanResult) !void {
    try writer.print("Total files: {d}\n", .{result.total_files});
    try writer.print("Total dirs: {d}\n", .{result.total_dirs});
    try writer.print("Total lines: {d}\n", .{result.total_lines});
    try writer.writeAll("\nDetected file types:\n");

    var iterator = result.ext_stats.iterator();
    while (iterator.next()) |ext| {
        try writer.print(
            "  {d} files {s} ({d} lines)\n",
            .{ ext.value_ptr.count, ext.key_ptr.*, ext.value_ptr.total_lines },
        );
    }
}
