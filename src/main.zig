const std = @import("std");
const app = @import("app.zig");
const cli = @import("cli/parse.zig");
const cli_config = @import("cli/config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("memory leak detected!", .{});
        }
    }

    const allocator = gpa.allocator();
    const options = try cli.parseArgs(allocator);

    if (options.show_help) {
        try cli.printHelp();
        return;
    }

    const config = try cli_config.Config.fromOptions(options);
    try app.run(allocator, config);
}
