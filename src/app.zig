const std = @import("std");
const walker = @import("walker.zig");
const render = @import("render.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    var result = try walker.scanCurrentDir(allocator);
    defer result.deinit(allocator);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try render.printSummary(stdout, &result);
    try stdout.flush();
}
