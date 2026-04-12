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

test "updateExtansionStats accumulates counts lines and bytes" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    try updateExtansionStats(allocator, &result, ".zig", 10, 100);
    try updateExtansionStats(allocator, &result, ".zig", 3, 25);
    try updateExtansionStats(allocator, &result, ".txt", 1, 5);

    const zig = result.ext_stats.get(".zig").?;
    const txt = result.ext_stats.get(".txt").?;

    try std.testing.expectEqual(@as(usize, 2), zig.count);
    try std.testing.expectEqual(@as(usize, 13), zig.total_lines);
    try std.testing.expectEqual(@as(usize, 125), zig.total_bytes);

    try std.testing.expectEqual(@as(usize, 1), txt.count);
    try std.testing.expectEqual(@as(usize, 1), txt.total_lines);
    try std.testing.expectEqual(@as(usize, 5), txt.total_bytes);
}
