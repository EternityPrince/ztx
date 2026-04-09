const std = @import("std");
const model = @import("../model.zig");
const walker = @import("../walker.zig");
const helper = @import("../helper/walker_helper.zig");
const stats = @import("../stats/ext_stats_update.zig");

pub fn handleFile(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    name: []const u8,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
) !void {
    const rel_path = try helper.joinRelativePath(allocator, prefix, name);
    defer allocator.free(rel_path);

    const path_copy = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(path_copy);

    var file = try dir.openFile(name, .{});
    defer file.close();

    const stat = try file.stat();
    const lines_count = try helper.countLinesInFile(allocator, &file);

    const ext = std.fs.path.extension(name);
    const ext_value = if (ext.len == 0) "[no extension]" else ext;

    const ext_copy = try allocator.dupe(u8, ext_value);
    errdefer allocator.free(ext_copy);

    try stats.updateExtansionStats(allocator, result, ext_value, lines_count);

    try result.entries.append(allocator, .{
        .file = .{
            .path = path_copy,
            .extansion = ext_copy,
            .depth_level = depth,
            .byte_size = stat.size,
            .line_count = lines_count,
        },
    });

    result.total_files += 1;
    result.total_lines += lines_count;
}
