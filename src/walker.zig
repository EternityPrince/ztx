const std = @import("std");
const model = @import("model.zig");
const helper = @import("helper/walker_helper.zig");
const dir_handler = @import("handler/dir_handler.zig");
const file_handler = @import("handler/file_handler.zig");

pub fn scanCurrentDir(allocator: std.mem.Allocator) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    var dir = try std.fs.cwd().openDir(".", .{
        .iterate = true,
    });
    defer dir.close();

    try walkDir(allocator, &dir, "", 0, &result);
    return result;
}

pub fn walkDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
) anyerror!void {
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        if (helper.shouldSkip(entry.name)) continue;

        switch (entry.kind) {
            .directory => try dir_handler.handleDirectory(allocator, dir, entry.name, prefix, depth, result),
            .file => try file_handler.handleFile(allocator, dir, entry.name, prefix, depth, result),
            else => {},
        }
    }
}
