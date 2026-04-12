const std = @import("std");
const app = @import("app.zig");
const cli = @import("cli/parse.zig");
const cli_config = @import("cli/config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("memory leak detected!\n", .{});
        }
    }

    const allocator = gpa.allocator();
    var parsed = try cli.parseArgs(allocator);
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .help => {
            try cli.printHelp();
            return;
        },
        .init => {
            try cli_config.initConfigFile();
            std.debug.print("Created .ztx.toml\n", .{});
            return;
        },
        .run => |run| {
            var config = try cli_config.Config.fromRunOptions(allocator, run);
            defer config.deinit(allocator);

            app.run(allocator, &config) catch |err| switch (err) {
                error.GitUnavailable => {
                    std.debug.print(
                        "git metadata is unavailable. Run inside a git repository or rerun without --changed.\n",
                        .{},
                    );
                    return err;
                },
                else => return err,
            };
        },
    }
}
