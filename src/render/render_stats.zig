const core = @import("render_stats_core.zig");
const std = @import("std");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;

pub fn printStats(writer: anytype, allocator: std.mem.Allocator, result: *const model.ScanResult, context: RenderContext) !void {
    return core.printStats(writer, allocator, result, context);
}

test {
    _ = @import("render_stats_core.zig");
}
