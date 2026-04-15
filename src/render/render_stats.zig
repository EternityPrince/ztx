const core = @import("render_stats_core.zig");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;

pub fn printStats(writer: anytype, result: *const model.ScanResult, context: RenderContext) !void {
    return core.printStats(writer, result, context);
}

test {
    _ = @import("render_stats_core.zig");
}
