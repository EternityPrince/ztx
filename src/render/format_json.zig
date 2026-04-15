const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");
const buildTreeNodes = @import("render_tree.zig").buildTreeNodes;
const kindLabel = @import("render_tree.zig").kindLabel;
const shared = @import("shared.zig");

pub fn printJson(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, config: *const cli.Config) !void {
    var files = try shared.collectSortedFiles(allocator, result, config.sort_mode, config.top_files);
    defer files.deinit(allocator);

    try writer.writeAll("{");

    try writer.writeAll("\"summary\":{");
    try writer.print("\"files\":{d},\"dirs\":{d},\"lines\":{d},\"bytes\":{d}", .{
        result.total_files,
        result.total_dirs,
        result.total_lines,
        result.total_bytes,
    });
    try writer.writeAll("},");

    var rows = try shared.collectSortedExtRows(allocator, result);
    defer rows.deinit(allocator);

    try writer.writeAll("\"types\":[");
    for (rows.items, 0..) |row, idx| {
        if (idx > 0) try writer.writeAll(",");
        try writer.writeAll("{");
        try writer.writeAll("\"ext\":");
        try shared.writeJsonString(writer, row.ext);
        try writer.writeAll(",");
        try writer.print("\"files\":{d},\"lines\":{d},\"bytes\":{d},", .{ row.stat.count, row.stat.total_lines, row.stat.total_bytes });
        try writer.print("\"share_files\":{d:.1},\"share_lines\":{d:.1},\"share_bytes\":{d:.1}", .{
            shared.sharePercent(row.stat.count, result.total_files),
            shared.sharePercent(row.stat.total_lines, result.total_lines),
            shared.sharePercent(row.stat.total_bytes, result.total_bytes),
        });
        try writer.writeAll("}");
    }
    try writer.writeAll("],");

    var tree_nodes = try buildTreeNodes(allocator, result);
    defer tree_nodes.deinit(allocator);

    try writer.writeAll("\"tree\":[");
    for (tree_nodes.items, 0..) |node, idx| {
        if (idx > 0) try writer.writeAll(",");
        try writer.writeAll("{\"path\":");
        try shared.writeJsonString(writer, node.path);
        try writer.print(
            ",\"kind\":\"{s}\",\"depth\":{d},\"files\":{d},\"lines\":{d},\"comments\":{d},\"bytes\":{d}}}",
            .{
                kindLabel(node.kind),
                node.depth,
                node.file_count,
                node.line_count,
                node.comment_line_count,
                node.byte_size,
            },
        );
    }
    try writer.writeAll("],");

    try writer.writeAll("\"files\":[");
    for (files.items, 0..) |file, idx| {
        if (idx > 0) try writer.writeAll(",");

        try writer.writeAll("{\"path\":");
        try shared.writeJsonString(writer, file.path);
        try writer.print(",\"line_count\":{d},\"byte_size\":{d}", .{ file.line_count, file.byte_size });

        if (config.show_content) {
            try writer.writeAll(",\"content\":");
            if (file.content) |content| {
                try shared.writeJsonString(writer, content);
            } else {
                try writer.writeAll("null");
            }
        }

        try writer.writeAll("}");
    }
    try writer.writeAll("],");

    try writer.writeAll("\"skipped\":{");
    try writer.print(
        "\"gitignore\":{d},\"builtin\":{d},\"binary\":{d},\"size_limit\":{d},\"content_policy\":{d},\"depth_limit\":{d},\"file_limit\":{d},\"symlink\":{d},\"permission\":{d}",
        .{
            result.skipped.gitignore,
            result.skipped.builtin,
            result.skipped.binary_or_unsupported,
            result.skipped.size_limit,
            result.skipped.content_policy,
            result.skipped.depth_limit,
            result.skipped.file_limit,
            result.skipped.symlink,
            result.skipped.permission,
        },
    );
    try writer.writeAll("}");

    try writer.writeAll("}\n");
}

pub fn validateJsonOutput(allocator: std.mem.Allocator, output: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, output, .{}) catch {
        return error.InvalidJsonOutput;
    };
    defer parsed.deinit();

    const root = try expectObject(parsed.value);

    const summary = try expectFieldObject(root, "summary");
    try expectNumberField(summary, "files");
    try expectNumberField(summary, "dirs");
    try expectNumberField(summary, "lines");
    try expectNumberField(summary, "bytes");

    const types = try expectFieldArray(root, "types");
    for (types.items) |type_entry| {
        const type_obj = try expectObject(type_entry);
        _ = try expectFieldString(type_obj, "ext");
        try expectNumberField(type_obj, "files");
        try expectNumberField(type_obj, "lines");
        try expectNumberField(type_obj, "bytes");
        try expectNumberField(type_obj, "share_files");
        try expectNumberField(type_obj, "share_lines");
        try expectNumberField(type_obj, "share_bytes");
    }

    const tree = try expectFieldArray(root, "tree");
    for (tree.items) |tree_entry| {
        const tree_obj = try expectObject(tree_entry);
        _ = try expectFieldString(tree_obj, "path");
        const kind = try expectFieldString(tree_obj, "kind");
        if (!std.mem.eql(u8, kind, "dir") and !std.mem.eql(u8, kind, "file")) {
            return error.InvalidJsonOutput;
        }
        try expectNumberField(tree_obj, "depth");
        try expectNumberField(tree_obj, "files");
        try expectNumberField(tree_obj, "lines");
        try expectNumberField(tree_obj, "comments");
        try expectNumberField(tree_obj, "bytes");
    }

    const files = try expectFieldArray(root, "files");
    for (files.items) |file_entry| {
        const file_obj = try expectObject(file_entry);
        _ = try expectFieldString(file_obj, "path");
        try expectNumberField(file_obj, "line_count");
        try expectNumberField(file_obj, "byte_size");

        if (file_obj.get("content")) |content| {
            switch (content) {
                .null, .string => {},
                else => return error.InvalidJsonOutput,
            }
        }
    }

    const skipped = try expectFieldObject(root, "skipped");
    const skipped_keys = [_][]const u8{
        "gitignore",
        "builtin",
        "binary",
        "size_limit",
        "content_policy",
        "depth_limit",
        "file_limit",
        "symlink",
        "permission",
    };
    for (skipped_keys) |key| {
        try expectNumberField(skipped, key);
    }
}

fn expectObject(value: std.json.Value) !std.json.ObjectMap {
    if (value != .object) return error.InvalidJsonOutput;
    return value.object;
}

fn expectArray(value: std.json.Value) !std.json.Array {
    if (value != .array) return error.InvalidJsonOutput;
    return value.array;
}

fn expectField(obj: std.json.ObjectMap, key: []const u8) !std.json.Value {
    return obj.get(key) orelse return error.InvalidJsonOutput;
}

fn expectFieldObject(obj: std.json.ObjectMap, key: []const u8) !std.json.ObjectMap {
    return expectObject(try expectField(obj, key));
}

fn expectFieldArray(obj: std.json.ObjectMap, key: []const u8) !std.json.Array {
    return expectArray(try expectField(obj, key));
}

fn expectFieldString(obj: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = try expectField(obj, key);
    if (value != .string) return error.InvalidJsonOutput;
    return value.string;
}

fn expectNumberField(obj: std.json.ObjectMap, key: []const u8) !void {
    try expectNumber(try expectField(obj, key));
}

fn expectNumber(value: std.json.Value) !void {
    switch (value) {
        .integer, .float, .number_string => {},
        else => return error.InvalidJsonOutput,
    }
}
