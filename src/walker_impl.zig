const std = @import("std");
const core = @import("walker_core.zig");
const cli = @import("cli/config.zig");
const model = @import("model.zig");

pub fn scan(allocator: std.mem.Allocator, config: *const cli.Config) !model.ScanResult {
    return core.scan(allocator, config);
}

pub fn makeTestConfig(allocator: std.mem.Allocator) !cli.Config {
    return core.makeTestConfig(allocator);
}

pub fn runWalkForTest(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    config: *const cli.Config,
) !model.ScanResult {
    return core.runWalkForTest(allocator, dir, config);
}

test {
    _ = @import("walker_impl_test.zig");
}
