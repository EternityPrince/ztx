const std = @import("std");
const types = @import("types.zig");

pub const RunOptions = struct {
    show_tree: ?bool = null,
    show_content: ?bool = null,
    show_stats: ?bool = null,
    color_mode: ?types.ColorMode = null,
    scan_mode: ?types.ScanMode = null,
    output_format: ?types.OutputFormat = null,
    profile: ?[]u8 = null,
    paths: std.ArrayList([]const u8) = .empty,
    max_depth: ?usize = null,
    max_files: ?usize = null,
    max_bytes: ?usize = null,
    changed_only: ?bool = null,

    pub fn deinit(self: *RunOptions, allocator: std.mem.Allocator) void {
        if (self.profile) |profile| allocator.free(profile);
        for (self.paths.items) |path| allocator.free(path);
        self.paths.deinit(allocator);
    }
};

pub const Command = union(enum) {
    run: RunOptions,
    init,
    help,
};

pub const ParsedArgs = struct {
    command: Command,

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        switch (self.command) {
            .run => |*run| run.deinit(allocator),
            else => {},
        }
    }
};

pub fn parseArgs(allocator: std.mem.Allocator) !ParsedArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    return parseArgsFrom(allocator, args);
}

fn parseArgsFrom(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var run = RunOptions{};
    errdefer run.deinit(allocator);

    if (args.len <= 1) {
        return .{ .command = .{ .run = run } };
    }

    const first = args[1];
    if (!isFlag(first)) {
        if (std.mem.eql(u8, first, "init")) {
            if (args.len > 2) {
                std.debug.print("unknown flag for init command: {s}\n", .{args[2]});
                try printHelp();
                return error.UnknownFlag;
            }
            return .{ .command = .init };
        }

        if (std.mem.eql(u8, first, "help")) {
            return .{ .command = .help };
        }

        std.debug.print("unknown command: {s}\n", .{first});
        try printHelp();
        return error.UnknownCommand;
    }

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .command = .help };
        }

        if (std.mem.eql(u8, arg, "-no-tree") or std.mem.eql(u8, arg, "--no-tree")) {
            run.show_tree = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--tree")) {
            run.show_tree = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-no-content") or std.mem.eql(u8, arg, "--no-content")) {
            run.show_content = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--content")) {
            run.show_content = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-no-stats") or std.mem.eql(u8, arg, "--no-stats")) {
            run.show_stats = false;
            continue;
        }
        if (std.mem.eql(u8, arg, "--stats")) {
            run.show_stats = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "-no-color")) {
            run.color_mode = .never;
            continue;
        }

        if (std.mem.eql(u8, arg, "-full")) {
            run.scan_mode = .full;
            continue;
        }

        if (std.mem.eql(u8, arg, "--changed")) {
            run.changed_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--all")) {
            run.changed_only = false;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--color=")) {
            run.color_mode = try types.parseColorMode(arg["--color=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--color")) {
            const value = try consumeValue(args, &index, "--color");
            run.color_mode = try types.parseColorMode(value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--scan-mode=")) {
            run.scan_mode = try types.parseScanMode(arg["--scan-mode=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--scan-mode")) {
            const value = try consumeValue(args, &index, "--scan-mode");
            run.scan_mode = try types.parseScanMode(value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--format=")) {
            run.output_format = try types.parseOutputFormat(arg["--format=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            const value = try consumeValue(args, &index, "--format");
            run.output_format = try types.parseOutputFormat(value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--profile=")) {
            const value = arg["--profile=".len..];
            if (run.profile) |existing| allocator.free(existing);
            run.profile = try allocator.dupe(u8, value);
            continue;
        }
        if (std.mem.eql(u8, arg, "--profile")) {
            const value = try consumeValue(args, &index, "--profile");
            if (run.profile) |existing| allocator.free(existing);
            run.profile = try allocator.dupe(u8, value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--path=")) {
            const value = arg["--path=".len..];
            try run.paths.append(allocator, try allocator.dupe(u8, value));
            continue;
        }
        if (std.mem.eql(u8, arg, "--path")) {
            const value = try consumeValue(args, &index, "--path");
            try run.paths.append(allocator, try allocator.dupe(u8, value));
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-depth=")) {
            run.max_depth = try parseUsize(arg["--max-depth=".len..], "--max-depth");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-depth")) {
            const value = try consumeValue(args, &index, "--max-depth");
            run.max_depth = try parseUsize(value, "--max-depth");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-files=")) {
            run.max_files = try parseUsize(arg["--max-files=".len..], "--max-files");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-files")) {
            const value = try consumeValue(args, &index, "--max-files");
            run.max_files = try parseUsize(value, "--max-files");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-bytes=")) {
            run.max_bytes = try parseUsize(arg["--max-bytes=".len..], "--max-bytes");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-bytes")) {
            const value = try consumeValue(args, &index, "--max-bytes");
            run.max_bytes = try parseUsize(value, "--max-bytes");
            continue;
        }

        std.debug.print("unknown flag: {s}\n", .{arg});
        try printHelp();
        return error.UnknownFlag;
    }

    return .{ .command = .{ .run = run } };
}

fn consumeValue(args: []const []const u8, index: *usize, flag_name: []const u8) ![]const u8 {
    index.* += 1;
    if (index.* >= args.len) {
        std.debug.print("missing value for {s}\n", .{flag_name});
        return error.MissingValue;
    }

    const value = args[index.*];
    if (isFlag(value)) {
        std.debug.print("missing value for {s}\n", .{flag_name});
        return error.MissingValue;
    }

    return value;
}

fn parseUsize(raw: []const u8, flag_name: []const u8) !usize {
    return std.fmt.parseInt(usize, raw, 10) catch {
        std.debug.print("invalid numeric value for {s}: {s}\n", .{ flag_name, raw });
        return error.InvalidNumber;
    };
}

fn isFlag(value: []const u8) bool {
    return value.len > 0 and value[0] == '-';
}

pub fn printHelp() !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\Usage:
        \\  ztx [flags]
        \\  ztx init
        \\
        \\Core flags (compatible):
        \\  -no-tree, -no-content, -no-stats, -no-color, -full
        \\
        \\Preferred flags:
        \\  --tree / --no-tree
        \\  --content / --no-content
        \\  --stats / --no-stats
        \\  --color <auto|always|never>
        \\  --scan-mode <default|full>
        \\  --format <text|markdown|json>
        \\  --profile <review|llm|stats|custom>
        \\  --path <dir-or-file> (repeatable)
        \\  --max-depth <n>
        \\  --max-files <n>
        \\  --max-bytes <n>
        \\  --changed (scan only changed tracked/staged files)
        \\  --all (disable changed-only mode)
        \\  -h, --help
        \\
        \\Examples:
        \\  ztx
        \\  ztx --stats --no-content
        \\  ztx --scan-mode full --path src --path build.zig
        \\  ztx --format markdown --profile llm
        \\  ztx --changed --format json
        \\  ztx init
        \\
    );

    try stdout.flush();
}

test "parse supports legacy and long aliases" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "-no-tree", "--content", "-full" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(@as(?bool, false), run.show_tree);
            try std.testing.expectEqual(@as(?bool, true), run.show_content);
            try std.testing.expectEqual(types.ScanMode.full, run.scan_mode.?);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse supports value flags and repeatable paths" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{
        "ztx",
        "--format=json",
        "--color",
        "always",
        "--path",
        "src",
        "--path=build.zig",
        "--max-depth",
        "2",
        "--max-files=20",
        "--max-bytes=1024",
        "--changed",
    });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(types.OutputFormat.json, run.output_format.?);
            try std.testing.expectEqual(types.ColorMode.always, run.color_mode.?);
            try std.testing.expectEqual(@as(usize, 2), run.paths.items.len);
            try std.testing.expectEqual(@as(usize, 2), run.max_depth.?);
            try std.testing.expectEqual(@as(usize, 20), run.max_files.?);
            try std.testing.expectEqual(@as(usize, 1024), run.max_bytes.?);
            try std.testing.expectEqual(@as(?bool, true), run.changed_only);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse init command" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "init" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .init => {},
        else => return error.TestUnexpectedResult,
    }
}
