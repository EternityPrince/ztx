const std = @import("std");
const model = @import("../model.zig");
const baseName = @import("../helper/render_helper.zig").baseName;
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;

const NodeKind = enum {
    dir,
    file,
};

const Node = struct {
    kind: NodeKind,
    path: []const u8,
    name: []const u8,
    parent: []const u8,
};

pub fn printTree(writer: anytype, result: *const model.ScanResult, context: RenderContext) !void {
    const style = context.style;

    try style.write(writer, ansi.section, "DIRECTORY TREE\n");

    var nodes = std.ArrayList(Node).empty;
    defer nodes.deinit(std.heap.page_allocator);

    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => |dir| {
                try nodes.append(std.heap.page_allocator, .{
                    .kind = .dir,
                    .path = dir.path,
                    .name = baseName(dir.path),
                    .parent = parentPath(dir.path),
                });
            },
            .file => |file| {
                try nodes.append(std.heap.page_allocator, .{
                    .kind = .file,
                    .path = file.path,
                    .name = baseName(file.path),
                    .parent = parentPath(file.path),
                });
            },
        }
    }

    var continuation = std.ArrayList(bool).empty;
    defer continuation.deinit(std.heap.page_allocator);

    try printChildren(writer, style, nodes.items, "", &continuation);
}

fn printChildren(writer: anytype, style: Style, nodes: []const Node, parent: []const u8, continuation: *std.ArrayList(bool)) !void {
    var children = std.ArrayList(usize).empty;
    defer children.deinit(std.heap.page_allocator);

    for (nodes, 0..) |node, idx| {
        if (std.mem.eql(u8, node.parent, parent)) {
            try children.append(std.heap.page_allocator, idx);
        }
    }

    std.mem.sort(usize, children.items, NodeSortContext{ .nodes = nodes }, nodeIndexLessThan);

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
                try style.print(writer, ansi.dir, "{s}/\n", .{node.name});
                try continuation.append(std.heap.page_allocator, !is_last);
                defer _ = continuation.pop();
                try printChildren(writer, style, nodes, node.path, continuation);
            },
            .file => try style.print(writer, ansi.file, "{s}\n", .{node.name}),
        }
    }
}

fn parentPath(path: []const u8) []const u8 {
    const separator = std.mem.lastIndexOfScalar(u8, path, '/');
    if (separator) |index| return path[0..index];
    return "";
}

const NodeSortContext = struct {
    nodes: []const Node,
};

fn nodeIndexLessThan(context: NodeSortContext, left_idx: usize, right_idx: usize) bool {
    const left = context.nodes[left_idx];
    const right = context.nodes[right_idx];

    if (left.kind != right.kind) return left.kind == .dir;
    return std.mem.order(u8, left.name, right.name) == .lt;
}

test "tree uses unicode branches and sorted output" {
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
        .extansion = ext,
        .line_count = 0,
        .byte_size = 0,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .dir = .{
        .path = b_dir,
        .depth_level = 0,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = z_file,
        .extansion = try allocator.dupe(u8, ".txt"),
        .line_count = 0,
        .byte_size = 0,
        .depth_level = 0,
        .content = null,
    } });
    try result.entries.append(allocator, .{ .dir = .{
        .path = a_dir,
        .depth_level = 0,
    } });
    try result.entries.append(allocator, .{ .file = .{
        .path = b_file,
        .extansion = try allocator.dupe(u8, ".txt"),
        .line_count = 0,
        .byte_size = 0,
        .depth_level = 0,
        .content = null,
    } });

    var buffer: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printTree(
        fbs.writer(),
        &result,
        .{
            .style = .{
                .use_color = false,
            },
        },
    );

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "DIRECTORY TREE") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "├── a/") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   ├── b/") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   │   └── f.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "│   └── z.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "└── m.txt") != null);
}
