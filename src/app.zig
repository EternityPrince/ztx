const std = @import("std");
const walker = @import("walker.zig");
const render = @import("render/render.zig");
const cli = @import("cli/config.zig");

pub fn run(allocator: std.mem.Allocator, config: *const cli.Config) !void {
    var result = try walker.scan(allocator, config);
    defer result.deinit(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try render.printStdout(stdout, allocator, &result, config);
    try stdout.flush();
}
