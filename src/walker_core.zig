const std = @import("std");
const model = @import("model.zig");
const helper = @import("helper/walker_helper.zig");
const stats = @import("stats/ext_stats_update.zig");
const policy = @import("policy/walker_ignore.zig");
const cli = @import("cli/config.zig");
const path_rules = @import("walker/path_rules.zig");
const changed_paths = @import("walker/changed_paths.zig");
const content_policy = @import("walker/content_policy.zig");

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
            error.AccessDenied => {
                result.skipped.permission += 1;
                continue;
            },
            else => return err,
        };

        switch (stat.kind) {
            .directory => {
                if (path_rules.isExcludedPath(config.exclude_patterns.items, path)) continue;

                try addDirectoryEntry(allocator, result, &known_dirs, path, path_rules.pathDepth(path));

                var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
                    error.AccessDenied => {
                        result.skipped.permission += 1;
                        continue;
                    },
                    else => return err,
                };
                defer dir.close();

                try walkDir(allocator, &dir, path, path_rules.pathDepth(path) + 1, result, config, &gitignore, &known_dirs);
            },
            .file => {
                if (!path_rules.shouldIncludeFile(config.include_patterns.items, config.exclude_patterns.items, path)) continue;
                try scanSingleFilePath(allocator, path, path_rules.pathDepth(path), result, config, &gitignore, &known_dirs);
            },
            .sym_link => {
                result.skipped.symlink += 1;
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

    while (true) {
        const next_entry = iterator.next() catch |err| switch (err) {
            error.AccessDenied => {
                result.skipped.permission += 1;
                continue;
            },
            else => return err,
        };
        const entry = next_entry orelse break;

        const rel_path = try helper.joinRelativePath(allocator, prefix, entry.name);
        defer allocator.free(rel_path);

        if (policy.pathSkipReason(entry.name, rel_path, entry.kind, gitignore)) |reason| {
            switch (reason) {
                .builtin => result.skipped.builtin += 1,
                .gitignore => result.skipped.gitignore += 1,
            }
            continue;
        }

        if (entry.kind == .sym_link) {
            result.skipped.symlink += 1;
            continue;
        }

        if (path_rules.isExcludedPath(config.exclude_patterns.items, rel_path)) continue;

        switch (entry.kind) {
            .directory => {
                try addDirectoryEntry(allocator, result, known_dirs, rel_path, depth);

                if (config.max_depth) |max_depth| {
                    if (depth >= max_depth) {
                        result.skipped.depth_limit += 1;
                        continue;
                    }
                }

                var child = dir.openDir(entry.name, .{ .iterate = true }) catch |err| switch (err) {
                    error.AccessDenied => {
                        result.skipped.permission += 1;
                        continue;
                    },
                    else => return err,
                };
                defer child.close();

                try walkDir(allocator, &child, rel_path, depth + 1, result, config, gitignore, known_dirs);
            },
            .file => {
                if (!path_rules.shouldIncludeFile(config.include_patterns.items, config.exclude_patterns.items, rel_path)) continue;
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

    var changed_paths_list = try changed_paths.collectChangedPaths(allocator, config.changed_base);
    defer {
        for (changed_paths_list.items) |path| allocator.free(path);
        changed_paths_list.deinit(allocator);
    }

    for (changed_paths_list.items) |path| {
        if (!path_rules.pathInScope(path, config.paths.items)) continue;
        if (path_rules.isExcludedPath(config.exclude_patterns.items, path)) continue;
        if (!path_rules.shouldIncludeFile(config.include_patterns.items, config.exclude_patterns.items, path)) continue;

        const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => {
                result.skipped.permission += 1;
                continue;
            },
            else => return err,
        };

        if (stat.kind == .sym_link) {
            result.skipped.symlink += 1;
            continue;
        }
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
            if (path_rules.pathDepth(path) > max_depth) {
                result.skipped.depth_limit += 1;
                continue;
            }
        }

        try ensureParentDirs(allocator, result, &known_dirs, path);
        try scanSingleFilePath(allocator, path, path_rules.pathDepth(path), result, config, &gitignore, &known_dirs);
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

    if (config.max_depth) |max_depth| {
        if (depth > max_depth) {
            result.skipped.depth_limit += 1;
            return;
        }
    }

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

    var file = std.fs.cwd().openFile(rel_path, .{}) catch |err| switch (err) {
        error.AccessDenied => {
            result.skipped.permission += 1;
            return;
        },
        else => return err,
    };
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
    if (config.max_depth) |max_depth| {
        if (depth > max_depth) {
            result.skipped.depth_limit += 1;
            return;
        }
    }

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

    var file = dir.openFile(name, .{}) catch |err| switch (err) {
        error.AccessDenied => {
            result.skipped.permission += 1;
            return;
        },
        else => return err,
    };
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

    if (try helper.isLikelyBinary(file)) {
        result.skipped.binary_or_unsupported += 1;
        return;
    }

    if (config.max_bytes) |max_bytes| {
        if (result.total_bytes + stat.size > max_bytes) {
            result.skipped.size_limit += 1;
            return;
        }
    }

    const content_excluded = content_policy.shouldExcludeContentByPolicy(config, file_name, rel_path);
    const capture_content = config.show_content and !content_excluded and stat.size <= config.max_content_bytes;
    if (config.show_content and content_excluded) {
        result.skipped.content_policy += 1;
    } else if (config.show_content and !capture_content) {
        result.skipped.size_limit += 1;
    }

    const file_data = try helper.readFileData(allocator, file, capture_content, file_name);
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
            .comment_line_count = file_data.comment_line_count,
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

pub fn makeTestConfig(allocator: std.mem.Allocator) !cli.Config {
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
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .changed_base = null,
        .include_patterns = std.ArrayList([]const u8).empty,
        .exclude_patterns = std.ArrayList([]const u8).empty,
        .strict_json = false,
        .compact = false,
        .sort_mode = .name,
        .tree_sort_mode = .name,
        .content_preset = .balanced,
        .content_exclude_patterns = std.ArrayList([]const u8).empty,
        .top_files = null,
        .profile_name = null,
    };
    try config.paths.append(allocator, try allocator.dupe(u8, "."));
    return config;
}

pub fn runWalkForTest(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    config: *const cli.Config,
) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    var ignore = policy.GitIgnore.initEmpty();
    defer ignore.deinit(allocator);

    var known_dirs = std.StringHashMap(void).init(allocator);
    defer known_dirs.deinit();

    try walkDir(allocator, dir, "", 0, &result, config, &ignore, &known_dirs);
    return result;
}

test {
    _ = @import("walker_impl_test.zig");
}
