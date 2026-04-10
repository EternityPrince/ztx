const std = @import("std");
const model = @import("model.zig");
const dir_handler = @import("handler/dir_handler.zig");
const file_handler = @import("handler/file_handler.zig");
const shouldSkip = @import("policy/walker_ignore.zig").shouldSkip;
const policy = @import("policy/walker_ignore.zig");
const cli = @import("cli/config.zig");

pub fn scanCurrentDir(allocator: std.mem.Allocator, config: cli.Config) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    var dir = try std.fs.cwd().openDir(".", .{
        .iterate = true,
    });
    defer dir.close();

    try walkDir(allocator, &dir, "", 0, &result, config);
    return result;
}

pub fn walkDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: cli.Config,
) anyerror!void {
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        if (shouldSkip(entry.name, entry.kind)) continue;

        switch (entry.kind) {
            .directory => try dir_handler.handleDirectory(allocator, dir, entry.name, prefix, depth, result, config),
            .file => {
                if (!policy.shouldScanFile(entry.name, config)) continue;
                try file_handler.handleFile(allocator, dir, entry.name, prefix, depth, result, config);
            },
            else => {},
        }
    }
}
