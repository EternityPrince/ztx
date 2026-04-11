const std = @import("std");
const model = @import("../model.zig");
const walker = @import("../walker.zig");
const helper = @import("../helper/walker_helper.zig");
const stats = @import("../stats/ext_stats_update.zig");
const cli = @import("../cli/config.zig");

pub fn handleFile(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    name: []const u8,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: cli.Config,
) !void {
    const rel_path = try helper.joinRelativePath(allocator, prefix, name);
    defer allocator.free(rel_path);

    const path_copy = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(path_copy);

    var file = try dir.openFile(name, .{});
    defer file.close();

    const stat = try file.stat();

    const file_data = if (config.show_content or config.show_stats)
        try helper.readFileData(allocator, &file, config.show_content)
    else
        helper.FileReadResult{
            .content = null,
            .line_count = 0,
        };
    errdefer if (file_data.content) |content| allocator.free(content);

    const ext = std.fs.path.extension(name);
    const ext_value = if (ext.len == 0) "[no extension]" else ext;

    const ext_copy = try allocator.dupe(u8, ext_value);
    errdefer allocator.free(ext_copy);

    if (config.show_stats) try stats.updateExtansionStats(allocator, result, ext_value, file_data.line_count, stat.size);

    try result.entries.append(allocator, .{
        .file = .{
            .path = path_copy,
            .extansion = ext_copy,
            .depth_level = depth,
            .byte_size = stat.size,
            .line_count = file_data.line_count,
            .content = file_data.content,
        },
    });

    result.total_files += 1;
    if (config.show_stats) {
        result.total_lines += file_data.line_count;
        result.total_bytes += stat.size;
    }
}
