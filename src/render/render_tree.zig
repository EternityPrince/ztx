const std = @import("std");
const model = @import("../model.zig");
const types = @import("../cli/types.zig");
const baseName = @import("../helper/render_helper.zig").baseName;
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;

pub const NodeKind = enum {
    dir,
    file,
};

pub const TreeNode = struct {
    kind: NodeKind,
    path: []const u8,
    name: []const u8,
    parent: []const u8,
    depth: usize,
    file_count: usize,
    line_count: usize,
    comment_line_count: usize,
    byte_size: usize,
};

pub fn printTree(
    writer: anytype,
    allocator: std.mem.Allocator,
    result: *const model.ScanResult,
    context: RenderContext,
    tree_sort_mode: types.TreeSortMode,
) !void {
    const style = context.style;

    try style.write(writer, ansi.section, "DIRECTORY TREE\n");

    var nodes = try buildTreeNodes(allocator, result);
    defer nodes.deinit(allocator);

    const badge_column = computeBadgeColumn(nodes.items);

    var continuation = std.ArrayList(bool).empty;
    defer continuation.deinit(allocator);

    try printChildren(writer, style, nodes.items, "", tree_sort_mode, badge_column, &continuation, allocator);
}

pub fn buildTreeNodes(allocator: std.mem.Allocator, result: *const model.ScanResult) !std.ArrayList(TreeNode) {
    var nodes = std.ArrayList(TreeNode).empty;
    errdefer nodes.deinit(allocator);

    var index_by_path = std.StringHashMap(usize).init(allocator);
    defer index_by_path.deinit();

    for (result.entries.items) |entry| {
        const node = switch (entry) {
            .dir => |dir| TreeNode{
                .kind = .dir,
                .path = dir.path,
                .name = baseName(dir.path),
                .parent = parentPath(dir.path),
                .depth = pathDepth(dir.path),
                .file_count = 0,
                .line_count = 0,
                .comment_line_count = 0,
                .byte_size = 0,
            },
            .file => |file| TreeNode{
                .kind = .file,
                .path = file.path,
                .name = baseName(file.path),
                .parent = parentPath(file.path),
                .depth = pathDepth(file.path),
                .file_count = 1,
                .line_count = file.line_count,
                .comment_line_count = file.comment_line_count,
                .byte_size = file.byte_size,
            },
        };

        try nodes.append(allocator, node);
        try index_by_path.put(node.path, nodes.items.len - 1);
    }

    for (nodes.items) |node| {
        if (node.kind != .file) continue;

        var parent = node.parent;
        while (parent.len > 0) {
            if (index_by_path.get(parent)) |idx| {
                var parent_node = &nodes.items[idx];
                if (parent_node.kind == .dir) {
                    parent_node.file_count += node.file_count;
                    parent_node.line_count += node.line_count;
                    parent_node.comment_line_count += node.comment_line_count;
                    parent_node.byte_size += node.byte_size;
                }
            }
            parent = parentPath(parent);
        }
    }

    return nodes;
}

pub fn kindLabel(kind: NodeKind) []const u8 {
    return switch (kind) {
        .dir => "dir",
        .file => "file",
    };
}

fn printChildren(
    writer: anytype,
    style: Style,
    nodes: []const TreeNode,
    parent: []const u8,
    tree_sort_mode: types.TreeSortMode,
    badge_column: usize,
    continuation: *std.ArrayList(bool),
    allocator: std.mem.Allocator,
) !void {
    var children = std.ArrayList(usize).empty;
    defer children.deinit(allocator);

    for (nodes, 0..) |node, idx| {
        if (std.mem.eql(u8, node.parent, parent)) {
            try children.append(allocator, idx);
        }
    }

    std.mem.sort(usize, children.items, NodeSortContext{
        .nodes = nodes,
        .tree_sort_mode = tree_sort_mode,
    }, nodeIndexLessThan);

    for (children.items, 0..) |node_idx, child_idx| {
        const is_last = child_idx + 1 == children.items.len;
        const node = nodes[node_idx];

        for (continuation.items) |has_more| {
            if (has_more) {
                try style.write(writer, ansi.tree, "│");
                try writer.writeAll("   ");
            } else {
                try writer.writeAll("    ");
            }
        }

        try style.write(writer, ansi.tree, if (is_last) "└── " else "├── ");
        switch (node.kind) {
            .dir => {
                try style.print(writer, ansi.dir, "{s}/", .{node.name});
                const label_width = continuation.items.len * 4 + 4 + node.name.len + 1;
                try writeBadgePadding(writer, label_width, badge_column);
                try printDirBadge(writer, style, node);
                try writer.writeAll("\n");

                try continuation.append(allocator, !is_last);
                defer _ = continuation.pop();
                try printChildren(writer, style, nodes, node.path, tree_sort_mode, badge_column, continuation, allocator);
            },
            .file => {
                try style.print(writer, ansi.file, "{s}", .{node.name});
                const label_width = continuation.items.len * 4 + 4 + node.name.len;
                try writeBadgePadding(writer, label_width, badge_column);
                try printFileBadge(writer, style, node);
                try writer.writeAll("\n");
            },
        }
    }
}

fn writeBadgePadding(writer: anytype, current_width: usize, badge_column: usize) !void {
    const target_width = if (badge_column > current_width) badge_column - current_width else 2;
    var i: usize = 0;
    while (i < target_width) : (i += 1) {
        try writer.writeAll(" ");
    }
}

fn computeBadgeColumn(nodes: []const TreeNode) usize {
    var max_label_width: usize = 0;
    for (nodes) |node| {
        const label_width = node.depth * 4 + 4 + node.name.len +
            (if (node.kind == .dir) @as(usize, 1) else @as(usize, 0));
        if (label_width > max_label_width) max_label_width = label_width;
    }
    return max_label_width + 2;
}

fn printDirBadge(writer: anytype, style: Style, node: TreeNode) !void {
    var byte_buf: [32]u8 = undefined;
    const human = try formatByteSize(&byte_buf, node.byte_size);
    try style.print(writer, ansi.label, "  [F:{d} L:{d} C:{d} B:{s}]", .{
        node.file_count,
        node.line_count,
        node.comment_line_count,
        human,
    });
}

fn printFileBadge(writer: anytype, style: Style, node: TreeNode) !void {
    var byte_buf: [32]u8 = undefined;
    const human = try formatByteSize(&byte_buf, node.byte_size);
    try style.print(writer, ansi.label, "  [L:{d} C:{d} B:{s}]", .{
        node.line_count,
        node.comment_line_count,
        human,
    });
}

fn formatByteSize(buffer: *[32]u8, bytes: usize) ![]const u8 {
    const units = [_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB" };

    if (bytes < 1024) {
        return std.fmt.bufPrint(buffer, "{d}B", .{bytes});
    }

    var value = @as(f64, @floatFromInt(bytes));
    var unit_index: usize = 0;
    while (value >= 1024 and unit_index + 1 < units.len) {
        value /= 1024;
        unit_index += 1;
    }

    return std.fmt.bufPrint(buffer, "{d:.1}{s}", .{ value, units[unit_index] });
}

fn parentPath(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '/');
    if (separator) |index| return path[0..index];
    return "";
}

fn pathDepth(path: []const u8) usize {
    if (path.len == 0) return 0;
    var depth: usize = 0;
    for (path) |char| {
        if (char == '/') depth += 1;
    }
    return depth;
}

const NodeSortContext = struct {
    nodes: []const TreeNode,
    tree_sort_mode: types.TreeSortMode,
};

fn nodeIndexLessThan(context: NodeSortContext, left_idx: usize, right_idx: usize) bool {
    const left = context.nodes[left_idx];
    const right = context.nodes[right_idx];

    if (left.kind != right.kind) return left.kind == .dir;

    return switch (context.tree_sort_mode) {
        .name => std.mem.order(u8, left.name, right.name) == .lt,
        .lines => {
            if (left.line_count != right.line_count) return left.line_count > right.line_count;
            if (left.byte_size != right.byte_size) return left.byte_size > right.byte_size;
            return std.mem.order(u8, left.name, right.name) == .lt;
        },
        .bytes => {
            if (left.byte_size != right.byte_size) return left.byte_size > right.byte_size;
            if (left.line_count != right.line_count) return left.line_count > right.line_count;
            return std.mem.order(u8, left.name, right.name) == .lt;
        },
    };
}

test "tree uses unicode branches and prints badges" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    const a_dir = try allocator.dupe(u8, "a");
    const b_dir = try allocator.dupe(u8, "a/b");
    const m_file = try allocator.dupe(u8, "m.txt");
    const z_file = try allocator.dupe(u8, "a/z.txt");
    const b_file = try allocator.dupe(u8, "a/b/f.txt");
    const ext = try allocator.dupe(u8, ".txt");

    try result.entries.append(allocator, .{ .file = .{
        .path = m_file,
        .extension = ext,
        .line_count = 7,
        .comment_line_count = 1,
        .byte_size = 1024,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .dir = .{
        .path = b_dir,
        .depth_level = 0,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = z_file,
        .extension = try allocator.dupe(u8, ".txt"),
        .line_count = 2,
        .comment_line_count = 1,
        .byte_size = 30,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .dir = .{
        .path = a_dir,
        .depth_level = 0,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = b_file,
        .extension = try allocator.dupe(u8, ".txt"),
        .line_count = 4,
        .comment_line_count = 2,
        .byte_size = 128,
        .depth_level = 0,
        .content = null,
    } });

    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printTree(
        fbs.writer(),
        allocator,
        &result,
        .{
            .style = .{
                .use_color = false,
            },
        },
        .name,
    );

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "├── a/  [F:2 L:6 C:3 B:158B]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   ├── b/  [F:1 L:4 C:2 B:128B]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   │   └── f.txt  [L:4 C:2 B:128B]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   └── z.txt  [L:2 C:1 B:30B]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── m.txt  [L:7 C:1 B:1.0KiB]") != null);
}

test "tree supports sorting by lines" {
    const allocator = std.testing.allocator;
    var result = model.ScanResult.init(allocator);
    defer result.deinit(allocator);

    try result.entries.append(allocator, .{ .file = .{
        .path = try allocator.dupe(u8, "a.txt"),
        .extension = try allocator.dupe(u8, ".txt"),
        .line_count = 1,
        .comment_line_count = 0,
        .byte_size = 5,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = try allocator.dupe(u8, "b.txt"),
        .extension = try allocator.dupe(u8, ".txt"),
        .line_count = 5,
        .comment_line_count = 0,
        .byte_size = 5,
        .depth_level = 0,
        .content = null,
    } });

    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try printTree(fbs.writer(), allocator, &result, .{ .style = .{ .use_color = false } }, .lines);

    const output = fbs.getWritten();
    const first_file = std.mem.indexOf(u8, output, "b.txt");
    const second_file = std.mem.indexOf(u8, output, "a.txt");
    try std.testing.expect(first_file != null);
    try std.testing.expect(second_file != null);
    try std.testing.expect(first_file.? < second_file.?);
}
