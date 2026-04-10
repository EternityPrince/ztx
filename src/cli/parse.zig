const std = @import("std");

pub const Options = struct {
    show_tree: bool = true,
    show_content: bool = true,
    show_stats: bool = true,
    show_help: bool = false,
};

const Arg = enum {
    no_tree,
    no_content,
    no_stats,
    help,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Options {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var options = Options{};

    for (args[1..]) |raw_arg| {
        const arg = parseRawArg(raw_arg) catch {
            std.debug.print("unknown flag: {s}\n", .{raw_arg});
            try printHelp();
            return error.UnknownFlag;
        };

        switch (arg) {
            .no_tree => options.show_tree = false,
            .no_content => options.show_content = false,
            .no_stats => options.show_stats = false,
            .help => options.show_help = true,
        }
    }

    return options;
}

fn parseRawArg(arg: []const u8) !Arg {
    if (std.mem.eql(u8, arg, "-no-tree")) return .no_tree;
    if (std.mem.eql(u8, arg, "-no-content")) return .no_content;
    if (std.mem.eql(u8, arg, "-no-stats")) return .no_stats;
    if (std.mem.eql(u8, arg, "--help")) return .help;
    if (std.mem.eql(u8, arg, "-h")) return .help;

    return error.UnknownFlag;
}

pub fn printHelp() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\Usage: ztx [-no-tree] [-no-content] [-no-stats]
        \\
        \\Flags:
        \\  -no-tree      do not print directory tree
        \\  -no-content   do not print file contents
        \\  -no-stats     do not print summary statistics
        \\  -h, --help    show help
        \\
    );

    try stdout.flush();
}

