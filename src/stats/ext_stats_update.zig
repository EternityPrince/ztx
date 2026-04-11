const std = @import("std");
const model = @import("../model.zig");

pub fn updateExtansionStats(
    allocator: std.mem.Allocator,
    result: *model.ScanResult,
    ext_value: []const u8,
    line_count: usize,
    byte_size: usize,
) !void {
    const gop = try result.ext_stats.getOrPut(ext_value);

    if (!gop.found_existing) {
        const map_key = try allocator.dupe(u8, ext_value);
        errdefer allocator.free(map_key);

        gop.key_ptr.* = map_key;
        gop.value_ptr.* = .{
            .count = 1,
            .total_lines = line_count,
            .total_bytes = byte_size,
        };
    } else {
        gop.value_ptr.*.total_lines += line_count;
        gop.value_ptr.*.total_bytes += byte_size;
        gop.value_ptr.*.count += 1;
    }
}
