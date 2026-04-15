const std = @import("std");
const parse = @import("parse_impl.zig");
const types = @import("types.zig");

const parseArgsFrom = parse.parseArgsFrom;

test "parse supports legacy and long aliases" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "-no-tree", "--content", "-full" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(@as(?bool, false), run.show_tree);
            try std.testing.expectEqual(@as(?bool, true), run.show_content);
            try std.testing.expectEqual(types.ScanMode.full, run.scan_mode.?);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse ai command uses llm profile" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "ai" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expect(run.profile != null);
            try std.testing.expectEqualStrings("llm", run.profile.?);
            try std.testing.expectEqual(@as(?bool, false), run.show_stats);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse ai command allows flag overrides" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "ai", "--content", "--format=json" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expect(run.profile != null);
            try std.testing.expectEqualStrings("llm", run.profile.?);
            try std.testing.expectEqual(@as(?bool, true), run.show_content);
            try std.testing.expectEqual(types.OutputFormat.json, run.output_format.?);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse ai command allows enabling stats explicitly" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "ai", "--stats" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expect(run.profile != null);
            try std.testing.expectEqualStrings("llm", run.profile.?);
            try std.testing.expectEqual(@as(?bool, true), run.show_stats);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse supports value flags and repeatable paths" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{
        "ztx",
        "--format=json",
        "--strict-json",
        "--compact",
        "--sort=size",
        "--tree-sort=bytes",
        "--content-preset",
        "none",
        "--color",
        "always",
        "--path",
        "src",
        "--path=build.zig",
        "--include=src/**",
        "--exclude",
        "**/*.bin",
        "--content-exclude",
        ".env*",
        "--content-exclude=README*",
        "--base",
        "origin/main",
        "--max-depth",
        "2",
        "--max-files=20",
        "--max-bytes=1024",
        "--top-files=10",
        "--changed",
    });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(types.OutputFormat.json, run.output_format.?);
            try std.testing.expectEqual(types.ColorMode.always, run.color_mode.?);
            try std.testing.expectEqual(@as(usize, 2), run.paths.items.len);
            try std.testing.expectEqual(@as(usize, 1), run.include_patterns.items.len);
            try std.testing.expectEqual(@as(usize, 1), run.exclude_patterns.items.len);
            try std.testing.expectEqual(@as(usize, 2), run.content_exclude_patterns.items.len);
            try std.testing.expectEqualStrings("origin/main", run.changed_base.?);
            try std.testing.expectEqual(@as(usize, 2), run.max_depth.?);
            try std.testing.expectEqual(@as(usize, 20), run.max_files.?);
            try std.testing.expectEqual(@as(usize, 1024), run.max_bytes.?);
            try std.testing.expectEqual(@as(usize, 10), run.top_files.?);
            try std.testing.expectEqual(types.SortMode.size, run.sort_mode.?);
            try std.testing.expectEqual(types.TreeSortMode.bytes, run.tree_sort_mode.?);
            try std.testing.expectEqual(types.ContentPreset.none, run.content_preset.?);
            try std.testing.expectEqual(@as(?bool, true), run.strict_json);
            try std.testing.expectEqual(@as(?bool, true), run.compact);
            try std.testing.expectEqual(@as(?bool, true), run.changed_only);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse init command" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "init" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .init => |init| {
            try std.testing.expect(!init.force);
            try std.testing.expect(!init.dry_run);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse init command supports force and dry-run flags" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "init", "--force", "--dry-run" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .init => |init| {
            try std.testing.expect(init.force);
            try std.testing.expect(init.dry_run);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse --all resets changed flags" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "--base", "origin/main", "--all" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(@as(?bool, false), run.changed_only);
            try std.testing.expect(run.changed_base == null);
        },
        else => return error.TestUnexpectedResult,
    }
}
