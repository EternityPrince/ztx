const std = @import("std");
const types = @import("../types.zig");
const file_types = @import("types.zig");
const values = @import("values.zig");

pub fn applyScanKey(allocator: std.mem.Allocator, patch: *file_types.ScanPatch, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "mode") or std.mem.eql(u8, key, "scan_mode")) {
        patch.scan_mode = try types.parseScanMode(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "paths")) {
        try replacePaths(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "include")) {
        try replaceIncludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "exclude")) {
        try replaceExcludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "max_depth")) {
        patch.max_depth = try values.parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "max_files")) {
        patch.max_files = try values.parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "max_bytes")) {
        patch.max_bytes = try values.parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "changed")) {
        patch.changed_only = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "changed_base")) {
        if (patch.changed_base) |existing| allocator.free(existing);
        patch.changed_base = try allocator.dupe(u8, try values.parseString(value));
        patch.changed_only = true;
        return;
    }

    return error.InvalidScanKey;
}

pub fn applyOutputKey(allocator: std.mem.Allocator, patch: *file_types.OutputPatch, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "tree")) {
        patch.show_tree = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "content")) {
        patch.show_content = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "stats")) {
        patch.show_stats = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "color")) {
        patch.color_mode = try types.parseColorMode(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "format")) {
        patch.output_format = try types.parseOutputFormat(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "strict_json")) {
        patch.strict_json = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "compact")) {
        patch.compact = try values.parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "sort")) {
        patch.sort_mode = try types.parseSortMode(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "tree_sort")) {
        patch.tree_sort_mode = try types.parseTreeSortMode(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "content_preset")) {
        patch.content_preset = try types.parseContentPreset(try values.parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "content_exclude")) {
        try replaceContentExcludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "top_files")) {
        patch.top_files = try values.parseUsize(value);
        return;
    }

    return error.InvalidOutputKey;
}

pub fn isScanKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "mode") or
        std.mem.eql(u8, key, "scan_mode") or
        std.mem.eql(u8, key, "paths") or
        std.mem.eql(u8, key, "include") or
        std.mem.eql(u8, key, "exclude") or
        std.mem.eql(u8, key, "max_depth") or
        std.mem.eql(u8, key, "max_files") or
        std.mem.eql(u8, key, "max_bytes") or
        std.mem.eql(u8, key, "changed") or
        std.mem.eql(u8, key, "changed_base");
}

pub fn isOutputKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "tree") or
        std.mem.eql(u8, key, "content") or
        std.mem.eql(u8, key, "stats") or
        std.mem.eql(u8, key, "color") or
        std.mem.eql(u8, key, "format") or
        std.mem.eql(u8, key, "strict_json") or
        std.mem.eql(u8, key, "compact") or
        std.mem.eql(u8, key, "sort") or
        std.mem.eql(u8, key, "tree_sort") or
        std.mem.eql(u8, key, "content_preset") or
        std.mem.eql(u8, key, "content_exclude") or
        std.mem.eql(u8, key, "top_files");
}

fn replacePaths(allocator: std.mem.Allocator, patch: *file_types.ScanPatch, value: []const u8) !void {
    const parsed_paths = try values.parseStringArray(allocator, value);
    errdefer {
        for (parsed_paths.items) |path| allocator.free(path);
        var mutable_paths = parsed_paths;
        mutable_paths.deinit(allocator);
    }

    patch.deinit(allocator);
    patch.has_paths = true;
    patch.paths = parsed_paths;
}

fn replaceIncludes(allocator: std.mem.Allocator, patch: *file_types.ScanPatch, value: []const u8) !void {
    const parsed_patterns = try values.parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_include_patterns) {
        for (patch.include_patterns.items) |pattern| allocator.free(pattern);
        patch.include_patterns.deinit(allocator);
    }
    patch.has_include_patterns = true;
    patch.include_patterns = parsed_patterns;
}

fn replaceExcludes(allocator: std.mem.Allocator, patch: *file_types.ScanPatch, value: []const u8) !void {
    const parsed_patterns = try values.parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_exclude_patterns) {
        for (patch.exclude_patterns.items) |pattern| allocator.free(pattern);
        patch.exclude_patterns.deinit(allocator);
    }
    patch.has_exclude_patterns = true;
    patch.exclude_patterns = parsed_patterns;
}

fn replaceContentExcludes(allocator: std.mem.Allocator, patch: *file_types.OutputPatch, value: []const u8) !void {
    const parsed_patterns = try values.parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_content_exclude_patterns) {
        for (patch.content_exclude_patterns.items) |pattern| allocator.free(pattern);
        patch.content_exclude_patterns.deinit(allocator);
    }
    patch.has_content_exclude_patterns = true;
    patch.content_exclude_patterns = parsed_patterns;
}
