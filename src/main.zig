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
        .init => |init| {
            if (init.dry_run) {
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                var stdout = &stdout_writer.interface;

                try stdout.writeAll(cli_config.initConfigTemplate());
                try stdout.flush();
                return;
            }

            const status = try cli_config.initConfigFile(init.force);
            switch (status) {
                .created => std.debug.print("Created .ztx.toml\n", .{}),
                .overwritten => std.debug.print("Overwrote .ztx.toml\n", .{}),
            }
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
                    std.process.exit(1);
                },
                error.InvalidJsonOutput => {
                    std.debug.print(
                        "strict JSON validation failed. Please report this with your command and repository shape.\n",
                        .{},
                    );
                    std.process.exit(1);
                },
                else => return err,
            };
        },
    }
}
