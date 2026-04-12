const std = @import("std");
const model = @import("model.zig");
const helper = @import("helper/walker_helper.zig");
const stats = @import("stats/ext_stats_update.zig");
const policy = @import("policy/walker_ignore.zig");
const cli = @import("cli/config.zig");

pub fn scan(allocator: std.mem.Allocator, config: *const cli.Config) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    if (config.changed_only) {
        try scanChangedFiles(allocator, config, &result);
    } else {
        try scanConfiguredPaths(allocator, config, &result);
    }

    return result;
}

fn scanConfiguredPaths(allocator: std.mem.Allocator, config: *const cli.Config, result: *model.ScanResult) !void {
    var gitignore = try policy.GitIgnore.loadFromCwd(allocator);
    defer gitignore.deinit(allocator);

    var known_dirs = std.StringHashMap(void).init(allocator);
    defer known_dirs.deinit();

    for (config.paths.items) |path| {
        if (std.mem.eql(u8, path, ".")) {
            var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
            defer dir.close();
            try walkDir(allocator, &dir, "", 0, result, config, &gitignore, &known_dirs);
            continue;
        }

        const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };

        switch (stat.kind) {
            .directory => {
                try addDirectoryEntry(allocator, result, &known_dirs, path, pathDepth(path));

                var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
                defer dir.close();

                try walkDir(allocator, &dir, path, pathDepth(path) + 1, result, config, &gitignore, &known_dirs);
            },
            .file => {
                try scanSingleFilePath(allocator, path, pathDepth(path), result, config, &gitignore, &known_dirs);
            },
            else => {},
        }
    }
}

fn walkDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    prefix: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: *const cli.Config,
    gitignore: *const policy.GitIgnore,
    known_dirs: *std.StringHashMap(void),
) !void {
    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        const rel_path = try helper.joinRelativePath(allocator, prefix, entry.name);
        defer allocator.free(rel_path);

        if (policy.pathSkipReason(entry.name, rel_path, entry.kind, gitignore)) |reason| {
            switch (reason) {
                .builtin => result.skipped.builtin += 1,
                .gitignore => result.skipped.gitignore += 1,
            }
            continue;
        }

        switch (entry.kind) {
            .directory => {
                if (config.max_depth) |max_depth| {
                    if (depth > max_depth) {
                        result.skipped.depth_limit += 1;
                        continue;
                    }
                }

                try addDirectoryEntry(allocator, result, known_dirs, rel_path, depth);

                var child = try dir.openDir(entry.name, .{ .iterate = true });
                defer child.close();

                try walkDir(allocator, &child, rel_path, depth + 1, result, config, gitignore, known_dirs);
            },
            .file => {
                try scanFileFromDir(allocator, dir, entry.name, rel_path, depth, result, config);
            },
            else => {},
        }
    }
}

fn scanChangedFiles(allocator: std.mem.Allocator, config: *const cli.Config, result: *model.ScanResult) !void {
    var gitignore = try policy.GitIgnore.loadFromCwd(allocator);
    defer gitignore.deinit(allocator);

    var known_dirs = std.StringHashMap(void).init(allocator);
    defer known_dirs.deinit();

    var changed_paths = try collectChangedPaths(allocator);
    defer {
        for (changed_paths.items) |path| allocator.free(path);
        changed_paths.deinit(allocator);
    }

    for (changed_paths.items) |path| {
        if (!pathInScope(path, config.paths.items)) continue;

        const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };

        if (stat.kind != .file) continue;

        const base_name = std.fs.path.basename(path);

        if (policy.pathSkipReason(base_name, path, .file, &gitignore)) |reason| {
            switch (reason) {
                .builtin => result.skipped.builtin += 1,
                .gitignore => result.skipped.gitignore += 1,
            }
            continue;
        }

        if (config.max_depth) |max_depth| {
            if (pathDepth(path) > max_depth) {
                result.skipped.depth_limit += 1;
                continue;
            }
        }

        try ensureParentDirs(allocator, result, &known_dirs, path);
        try scanSingleFilePath(allocator, path, pathDepth(path), result, config, &gitignore, &known_dirs);
    }
}

fn scanSingleFilePath(
    allocator: std.mem.Allocator,
    rel_path: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: *const cli.Config,
    gitignore: *const policy.GitIgnore,
    known_dirs: *std.StringHashMap(void),
) !void {
    _ = gitignore;
    _ = known_dirs;

    const base_name = std.fs.path.basename(rel_path);
    if (!policy.shouldScanFile(base_name, config.scan_mode)) {
        result.skipped.binary_or_unsupported += 1;
        return;
    }

    if (config.max_files) |limit| {
        if (result.total_files >= limit) {
            result.skipped.file_limit += 1;
            return;
        }
    }

    var file = try std.fs.cwd().openFile(rel_path, .{});
    defer file.close();

    try appendFile(allocator, &file, base_name, rel_path, depth, result, config);
}

fn scanFileFromDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    name: []const u8,
    rel_path: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: *const cli.Config,
) !void {
    if (!policy.shouldScanFile(name, config.scan_mode)) {
        result.skipped.binary_or_unsupported += 1;
        return;
    }

    if (config.max_files) |limit| {
        if (result.total_files >= limit) {
            result.skipped.file_limit += 1;
            return;
        }
    }

    var file = try dir.openFile(name, .{});
    defer file.close();

    try appendFile(allocator, &file, name, rel_path, depth, result, config);
}

fn appendFile(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    file_name: []const u8,
    rel_path: []const u8,
    depth: usize,
    result: *model.ScanResult,
    config: *const cli.Config,
) !void {
    const stat = try file.stat();

    if (config.max_bytes) |max_bytes| {
        if (result.total_bytes + stat.size > max_bytes) {
            result.skipped.size_limit += 1;
            return;
        }
    }

    const capture_content = config.show_content and stat.size <= config.max_content_bytes;
    if (config.show_content and !capture_content) {
        result.skipped.size_limit += 1;
    }

    const file_data = try helper.readFileData(allocator, file, capture_content);
    errdefer if (file_data.content) |content| allocator.free(content);

    const ext = std.fs.path.extension(file_name);
    const ext_value = if (ext.len == 0) "[no extension]" else ext;

    const path_copy = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(path_copy);

    const ext_copy = try allocator.dupe(u8, ext_value);
    errdefer allocator.free(ext_copy);

    try stats.updateExtensionStats(allocator, result, ext_value, file_data.line_count, stat.size);

    try result.entries.append(allocator, .{
        .file = .{
            .path = path_copy,
            .extension = ext_copy,
            .depth_level = depth,
            .byte_size = stat.size,
            .line_count = file_data.line_count,
            .content = file_data.content,
        },
    });

    result.total_files += 1;
    result.total_lines += file_data.line_count;
    result.total_bytes += stat.size;
}

fn addDirectoryEntry(
    allocator: std.mem.Allocator,
    result: *model.ScanResult,
    known_dirs: *std.StringHashMap(void),
    path: []const u8,
    depth: usize,
) !void {
    if (known_dirs.contains(path)) return;

    const path_copy = try allocator.dupe(u8, path);
    errdefer allocator.free(path_copy);

    try result.entries.append(allocator, .{
        .dir = .{
            .path = path_copy,
            .depth_level = depth,
        },
    });

    try known_dirs.put(path_copy, {});
    result.total_dirs += 1;
}

fn ensureParentDirs(
    allocator: std.mem.Allocator,
    result: *model.ScanResult,
    known_dirs: *std.StringHashMap(void),
    path: []const u8,
) !void {
    var start: usize = 0;
    var depth: usize = 0;

    while (std.mem.indexOfScalarPos(u8, path, start, '/')) |idx| {
        const dir_path = path[0..idx];
        if (dir_path.len > 0) {
            try addDirectoryEntry(allocator, result, known_dirs, dir_path, depth);
            depth += 1;
        }
        start = idx + 1;
    }
}

fn collectChangedPaths(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var set = std.StringHashMap(void).init(allocator);
    defer set.deinit();

    var list = std.ArrayList([]const u8).empty;
    errdefer {
        for (list.items) |path| allocator.free(path);
        list.deinit(allocator);
    }

    try collectGitDiffPaths(allocator, &set, &list, &.{ "git", "diff", "--name-only" });
    try collectGitDiffPaths(allocator, &set, &list, &.{ "git", "diff", "--name-only", "--cached" });

    std.mem.sort([]const u8, list.items, {}, lessString);
    return list;
}

fn collectGitDiffPaths(
    allocator: std.mem.Allocator,
    set: *std.StringHashMap(void),
    list: *std.ArrayList([]const u8),
    argv: []const []const u8,
) !void {
    const output = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.GitUnavailable,
        else => return err,
    };
    defer allocator.free(output.stdout);
    defer allocator.free(output.stderr);

    switch (output.term) {
        .Exited => |code| {
            if (code != 0) return error.GitUnavailable;
        },
        else => return error.GitUnavailable,
    }

    var lines = std.mem.splitScalar(u8, output.stdout, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;

        if (set.contains(line)) continue;

        const path_copy = try allocator.dupe(u8, line);
        errdefer allocator.free(path_copy);

        try list.append(allocator, path_copy);
        errdefer _ = list.pop();
        try set.put(path_copy, {});
    }
}

fn lessString(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.order(u8, left, right) == .lt;
}

fn pathDepth(path: []const u8) usize {
    if (path.len == 0) return 0;

    var depth: usize = 0;
    for (path) |char| {
        if (char == '/') depth += 1;
    }

    return depth;
}

fn pathInScope(path: []const u8, scopes: []const []const u8) bool {
    for (scopes) |scope| {
        if (std.mem.eql(u8, scope, ".")) return true;
        if (std.mem.eql(u8, path, scope)) return true;

        var joined: [512]u8 = undefined;
        const prefix = std.fmt.bufPrint(&joined, "{s}/", .{scope}) catch continue;
        if (std.mem.startsWith(u8, path, prefix)) return true;
    }

    return false;
}

test "pathDepth counts nested separators" {
    try std.testing.expectEqual(@as(usize, 0), pathDepth("main.zig"));
    try std.testing.expectEqual(@as(usize, 1), pathDepth("src/main.zig"));
    try std.testing.expectEqual(@as(usize, 3), pathDepth("a/b/c/main.zig"));
}

test "pathInScope supports dot and nested scopes" {
    try std.testing.expect(pathInScope("src/main.zig", &.{ "." }));
    try std.testing.expect(pathInScope("src/main.zig", &.{ "src" }));
    try std.testing.expect(pathInScope("src/main.zig", &.{ "src/main.zig" }));
    try std.testing.expect(!pathInScope("pkg/file.zig", &.{ "src" }));
}

test "scan respects max-files limit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "a.zig", .data = "const a = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "b.zig", .data = "const b = 2;\n" });

    var config = cli.Config{
        .show_content = false,
        .show_tree = true,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .text,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = 1,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .profile_name = null,
    };
    defer config.deinit(allocator);

    try config.paths.append(allocator, try allocator.dupe(u8, "."));

    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    var ignore = policy.GitIgnore.initEmpty();
    defer ignore.deinit(allocator);

    var known_dirs = std.StringHashMap(void).init(allocator);
    defer known_dirs.deinit();

    try walkDir(allocator, &tmp.dir, "", 0, &result, &config, &ignore, &known_dirs);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.file_limit);
}
