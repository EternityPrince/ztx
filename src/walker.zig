const impl = @import("walker_impl.zig");
const std = @import("std");
const cli = @import("cli/config.zig");
const model = @import("model.zig");

pub fn scan(allocator: std.mem.Allocator, config: *const cli.Config) !model.ScanResult {
    return impl.scan(allocator, config);
}
