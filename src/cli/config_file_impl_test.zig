const std = @import("std");
const types = @import("types.zig");
const cfg = @import("config_file_impl.zig");

const parseToml = cfg.parseToml;
const writeDefaultToDir = cfg.writeDefaultToDir;
const defaultTemplate = cfg.defaultTemplate;
const WriteStatus = cfg.WriteStatus;

test "parseToml reads scan output and profile sections" {
    const allocator = std.testing.allocator;
    var parsed = try parseToml(allocator,
        \\[scan]
        \\mode = "full"
        \\paths = ["src", "build.zig"]
        \\include = ["src/**"]
        \\exclude = ["**/*.bin"]
        \\max_depth = 2
        \\changed = true
        \\changed_base = "origin/main"
        \\
        \\[output]
        \\tree = true
        \\content = false
        \\stats = true
        \\format = "json"
        \\color = "never"
        \\strict_json = true
        \\compact = true
        \\sort = "size"
        \\tree_sort = "lines"
        \\content_preset = "none"
        \\content_exclude = ["README*", ".env*"]
        \\top_files = 50
        \\
        \\[profiles.custom]
        \\content = true
        \\format = "markdown"
        \\tree_sort = "bytes"
        \\
    );
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(types.ScanMode.full, parsed.scan.scan_mode.?);
    try std.testing.expect(parsed.scan.has_paths);
    try std.testing.expectEqual(@as(usize, 2), parsed.scan.paths.items.len);
    try std.testing.expect(parsed.scan.has_include_patterns);
    try std.testing.expect(parsed.scan.has_exclude_patterns);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.exclude_patterns.items.len);
    try std.testing.expectEqual(@as(?usize, 2), parsed.scan.max_depth);
    try std.testing.expectEqual(@as(?bool, true), parsed.scan.changed_only);
    try std.testing.expectEqualStrings("origin/main", parsed.scan.changed_base.?);

    try std.testing.expectEqual(types.OutputFormat.json, parsed.output.output_format.?);
    try std.testing.expectEqual(types.ColorMode.never, parsed.output.color_mode.?);
    try std.testing.expectEqual(@as(?bool, true), parsed.output.strict_json);
    try std.testing.expectEqual(@as(?bool, true), parsed.output.compact);
    try std.testing.expectEqual(types.SortMode.size, parsed.output.sort_mode.?);
    try std.testing.expectEqual(types.TreeSortMode.lines, parsed.output.tree_sort_mode.?);
    try std.testing.expectEqual(types.ContentPreset.none, parsed.output.content_preset.?);
    try std.testing.expect(parsed.output.has_content_exclude_patterns);
    try std.testing.expectEqual(@as(usize, 2), parsed.output.content_exclude_patterns.items.len);
    try std.testing.expectEqual(@as(?usize, 50), parsed.output.top_files);

    const custom = parsed.getProfile("custom").?;
    try std.testing.expectEqual(@as(?bool, true), custom.output.show_content);
    try std.testing.expectEqual(types.OutputFormat.markdown, custom.output.output_format.?);
    try std.testing.expectEqual(types.TreeSortMode.bytes, custom.output.tree_sort_mode.?);
}

test "scan paths key does not reset previously parsed scan patch fields" {
    const allocator = std.testing.allocator;
    var parsed = try parseToml(allocator,
        \\[scan]
        \\include = ["src/**"]
        \\exclude = ["**/*.bin"]
        \\changed_base = "origin/main"
        \\paths = ["src", "build.zig"]
        \\
    );
    defer parsed.deinit(allocator);

    try std.testing.expect(parsed.scan.has_paths);
    try std.testing.expectEqual(@as(usize, 2), parsed.scan.paths.items.len);
    try std.testing.expect(parsed.scan.has_include_patterns);
    try std.testing.expect(parsed.scan.has_exclude_patterns);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.exclude_patterns.items.len);
    try std.testing.expect(parsed.scan.changed_base != null);
    try std.testing.expectEqualStrings("origin/main", parsed.scan.changed_base.?);
    try std.testing.expectEqual(@as(?bool, true), parsed.scan.changed_only);
}

test "writeDefaultToDir supports overwrite mode" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const first = try writeDefaultToDir(&tmp.dir, false);
    try std.testing.expectEqual(WriteStatus.created, first);

    try tmp.dir.writeFile(.{
        .sub_path = ".ztx.toml",
        .data = "legacy=true\n",
    });

    const second = try writeDefaultToDir(&tmp.dir, true);
    try std.testing.expectEqual(WriteStatus.overwritten, second);

    const rendered = try tmp.dir.readFileAlloc(std.testing.allocator, ".ztx.toml", 1_000_000);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(defaultTemplate(), rendered);
}
