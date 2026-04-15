const std = @import("std");
const core = @import("render_tree_core.zig");
const model = @import("../model.zig");
const types = @import("../cli/types.zig");
const RenderContext = @import("context.zig").RenderContext;

pub const NodeKind = core.NodeKind;
pub const TreeNode = core.TreeNode;

pub fn printTree(
    writer: anytype,
    allocator: std.mem.Allocator,
    result: *const model.ScanResult,
    context: RenderContext,
    tree_sort_mode: types.TreeSortMode,
) !void {
    return core.printTree(writer, allocator, result, context, tree_sort_mode);
}

pub fn buildTreeNodes(allocator: std.mem.Allocator, result: *const model.ScanResult) !std.ArrayList(TreeNode) {
    return core.buildTreeNodes(allocator, result);
}

pub fn kindLabel(kind: NodeKind) []const u8 {
    return core.kindLabel(kind);
}

test {
    _ = @import("render_tree_core.zig");
}
