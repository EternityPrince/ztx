const std = @import("std");
const config_mod = @import("config_impl.zig");
const parse = @import("parse.zig");

const Config = config_mod.Config;
const OutputFormat = config_mod.OutputFormat;
const SortMode = config_mod.SortMode;
const TreeSortMode = config_mod.TreeSortMode;

test "defaults can be overridden by profile and cli flags" {
    const allocator = std.testing.allocator;

    var options = parse.RunOptions{};
    defer options.deinit(allocator);

    options.profile = try allocator.dupe(u8, "stats");
    options.show_content = true;
    options.output_format = .json;
    options.strict_json = true;
    options.sort_mode = .size;
    options.top_files = 25;
    options.changed_base = try allocator.dupe(u8, "origin/main");
    try options.include_patterns.append(allocator, try allocator.dupe(u8, "src/**"));
    try options.exclude_patterns.append(allocator, try allocator.dupe(u8, "**/*.bin"));

    var config = try Config.fromRunOptions(allocator, options);
    defer config.deinit(allocator);

    try std.testing.expect(!config.show_tree);
    try std.testing.expect(config.show_content);
    try std.testing.expect(config.show_stats);
    try std.testing.expectEqual(OutputFormat.json, config.output_format);
    try std.testing.expect(config.strict_json);
    try std.testing.expectEqual(SortMode.size, config.sort_mode);
    try std.testing.expectEqual(@as(?usize, 25), config.top_files);
    try std.testing.expect(config.changed_only);
    try std.testing.expectEqualStrings("origin/main", config.changed_base.?);
    try std.testing.expectEqual(@as(usize, 1), config.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), config.exclude_patterns.items.len);
}

test "default config outputs tree only" {
    const allocator = std.testing.allocator;
    var options = parse.RunOptions{};
    defer options.deinit(allocator);

    var config = try Config.fromRunOptions(allocator, options);
    defer config.deinit(allocator);

    try std.testing.expect(!config.show_content);
    try std.testing.expect(config.show_tree);
    try std.testing.expect(!config.show_stats);
}

test "llm-token profile is markdown and token-oriented" {
    const allocator = std.testing.allocator;
    var options = parse.RunOptions{};
    defer options.deinit(allocator);

    options.profile = try allocator.dupe(u8, "llm-token");

    var config = try Config.fromRunOptions(allocator, options);
    defer config.deinit(allocator);

    try std.testing.expectEqual(OutputFormat.markdown, config.output_format);
    try std.testing.expect(config.show_tree);
    try std.testing.expect(config.show_stats);
    try std.testing.expect(!config.show_content);
    try std.testing.expectEqual(TreeSortMode.lines, config.tree_sort_mode);
}
