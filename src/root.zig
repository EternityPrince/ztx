const std = @import("std");

pub const Config = @import("cli/config.zig").Config;
pub const parseArgs = @import("cli/parse.zig").parseArgs;
pub const printHelp = @import("cli/parse.zig").printHelp;
pub const scan = @import("walker.zig").scan;
pub const render = @import("render/render.zig").printStdout;
pub const ScanResult = @import("model.zig").ScanResult;

pub fn run(allocator: std.mem.Allocator, config: *const Config) !void {
    return @import("app.zig").run(allocator, config);
}
