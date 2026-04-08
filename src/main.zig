const std = @import("std");
const app = @import("app.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("memory leak detected!", .{});
        }
    }

    const allocator = gpa.allocator();

    try app.run(allocator);
}
