const std = @import("std");
const model = @import("../model.zig");
const helper = @import("../helper/walker_helper.zig");
const walker = @import("../walker.zig");
const cli = @import("../cli/config.zig");

pub fn handleDirectory(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    name: []const u8,
    prefix: []const u8,
    depht: usize,
    result: *model.ScanResult,
    config: cli.Config,
) !void {
    const rel_path = try helper.joinRelativePath(allocator, prefix, name);
    defer allocator.free(rel_path);

    const path_copy = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(path_copy);

    try result.entries.append(allocator, .{
        .dir = .{
            .depth_level = depht,
            .path = path_copy,
        },
    });

    result.total_dirs += 1;

    var child = try dir.openDir(name, .{ .iterate = true });
    defer child.close();

    try walker.walkDir(allocator, &child, rel_path, depht + 1, result, config);
}
