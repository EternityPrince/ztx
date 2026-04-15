const std = @import("std");

pub fn collectChangedPaths(allocator: std.mem.Allocator, base_ref: ?[]const u8) !std.ArrayList([]const u8) {
    return collectChangedPathsInCwd(allocator, null, base_ref);
}

pub fn collectChangedPathsInCwd(
    allocator: std.mem.Allocator,
    cwd: ?[]const u8,
    base_ref: ?[]const u8,
) !std.ArrayList([]const u8) {
    var set = std.StringHashMap(void).init(allocator);
    defer set.deinit();

    var list = std.ArrayList([]const u8).empty;
    errdefer {
        for (list.items) |path| allocator.free(path);
        list.deinit(allocator);
    }

    if (base_ref) |base| {
        const merge_base_spec = try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base});
        defer allocator.free(merge_base_spec);
        try collectGitDiffPaths(allocator, &set, &list, &.{ "git", "diff", "--name-only", merge_base_spec }, cwd);
    }

    try collectGitDiffPaths(allocator, &set, &list, &.{ "git", "diff", "--name-only" }, cwd);
    try collectGitDiffPaths(allocator, &set, &list, &.{ "git", "diff", "--name-only", "--cached" }, cwd);

    std.mem.sort([]const u8, list.items, {}, lessString);
    return list;
}

fn collectGitDiffPaths(
    allocator: std.mem.Allocator,
    set: *std.StringHashMap(void),
    list: *std.ArrayList([]const u8),
    argv: []const []const u8,
    cwd: ?[]const u8,
) !void {
    const output = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
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
