const std = @import("std");
const model = @import("model.zig");
const dir_handler = @import("handler/dir_handler.zig");
const file_handler = @import("handler/file_handler.zig");
const policy = @import("policy/walker_ignore.zig");
const helper = @import("helper/walker_helper.zig");
const cli = @import("cli/config.zig");

pub fn scanCurrentDir(allocator: std.mem.Allocator, config: cli.Config) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    var gitignore = try policy.GitIgnore.loadFromCwd(allocator);
    defer gitignore.deinit(allocator);

    var dir = try std.fs.cwd().openDir(".", .{
        .iterate = true,
    });
    defer dir.close();

    try walkDir(allocator, &dir, "", 0, &result, config, &gitignore);
    return result;
}

pub fn walkDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: cli.Config,
    gitignore: *const policy.GitIgnore,
) anyerror!void {
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        const rel_path = try helper.joinRelativePath(allocator, prefix, entry.name);
        defer allocator.free(rel_path);

        if (policy.shouldSkip(entry.name, rel_path, entry.kind, gitignore)) continue;

        switch (entry.kind) {
            .directory => try dir_handler.handleDirectory(allocator, dir, entry.name, prefix, depth, result, config, gitignore),
            .file => {
                if (!policy.shouldScanFile(entry.name, config)) continue;
                try file_handler.handleFile(allocator, dir, entry.name, prefix, depth, result, config);
            },
            else => {},
        }
    }
}

fn testConfig(scan_mode: cli.ScanMode, show_stats: bool) cli.Config {
    return .{
        .show_content = false,
        .show_tree = true,
        .show_help = false,
        .show_stats = show_stats,
        .use_color = false,
        .scan_mode = scan_mode,
    };
}

test "walkDir respects gitignore and default scan mode" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "keep.zig",
        .data = "const keep = true;\n",
    });
    try tmp.dir.writeFile(.{
        .sub_path = "ignored.txt",
        .data = "ignored\n",
    });
    try tmp.dir.writeFile(.{
        .sub_path = "skip.bin",
        .data = "bin",
    });
    try tmp.dir.makePath("sub");
    try tmp.dir.writeFile(.{
        .sub_path = "sub/inner.zig",
        .data = "const inner = true;\n",
    });

    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    var ignore = try policy.GitIgnore.loadFromContent(allocator,
        \\ignored.txt
        \\sub/
        \\
    );
    defer ignore.deinit(allocator);

    try walkDir(allocator, &tmp.dir, "", 0, &result, testConfig(.default, true), &ignore);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, 0), result.total_dirs);
    try std.testing.expectEqual(@as(usize, 1), result.total_lines);
    try std.testing.expectEqual(@as(usize, "const keep = true;\n".len), result.total_bytes);
    try std.testing.expectEqual(@as(usize, 1), result.entries.items.len);

    switch (result.entries.items[0]) {
        .file => |file| try std.testing.expectEqualStrings("keep.zig", file.path),
        .dir => return error.TestUnexpectedResult,
    }
}

test "walkDir full mode includes non-source extensions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "main.zig",
        .data = "const main = 1;\n",
    });
    try tmp.dir.writeFile(.{
        .sub_path = "data.bin",
        .data = "\x00\x01\x02",
    });

    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    var ignore = policy.GitIgnore.initEmpty();
    defer ignore.deinit(allocator);

    try walkDir(allocator, &tmp.dir, "", 0, &result, testConfig(.full, false), &ignore);

    try std.testing.expectEqual(@as(usize, 2), result.total_files);
    try std.testing.expectEqual(@as(usize, 0), result.total_lines);
    try std.testing.expectEqual(@as(usize, 0), result.total_bytes);
}
