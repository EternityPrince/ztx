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
    changed_base: ?[]u8 = null,
    include_patterns: std.ArrayList([]const u8) = .empty,
    exclude_patterns: std.ArrayList([]const u8) = .empty,
    strict_json: ?bool = null,
    compact: ?bool = null,
    sort_mode: ?types.SortMode = null,
    tree_sort_mode: ?types.TreeSortMode = null,
    content_preset: ?types.ContentPreset = null,
    content_exclude_patterns: std.ArrayList([]const u8) = .empty,
    top_files: ?usize = null,

    pub fn deinit(self: *RunOptions, allocator: std.mem.Allocator) void {
        if (self.profile) |profile| allocator.free(profile);
        if (self.changed_base) |base| allocator.free(base);
        for (self.paths.items) |path| allocator.free(path);
        for (self.include_patterns.items) |pattern| allocator.free(pattern);
        for (self.exclude_patterns.items) |pattern| allocator.free(pattern);
        for (self.content_exclude_patterns.items) |pattern| allocator.free(pattern);
        self.paths.deinit(allocator);
        self.include_patterns.deinit(allocator);
        self.exclude_patterns.deinit(allocator);
        self.content_exclude_patterns.deinit(allocator);
    }
};

pub const InitOptions = struct {
    force: bool = false,
    dry_run: bool = false,
};

pub const Command = union(enum) {
    run: RunOptions,
    init: InitOptions,
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

const RunParseStatus = enum {
    ok,
    help,
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
            return .{ .command = .{ .init = try parseInitArgs(args[2..]) } };
        }

        if (std.mem.eql(u8, first, "help")) {
            return .{ .command = .help };
        }

        if (std.mem.eql(u8, first, "ai")) {
            run.profile = try allocator.dupe(u8, "llm-token");
            const status = try parseRunFlags(allocator, &run, args[2..]);
            if (status == .help) return .{ .command = .help };
            return .{ .command = .{ .run = run } };
        }

        std.debug.print("unknown command: {s}\n", .{first});
        try printHelp();
        return error.UnknownCommand;
    }

    const status = try parseRunFlags(allocator, &run, args[1..]);
    if (status == .help) return .{ .command = .help };

    return .{ .command = .{ .run = run } };
}

fn parseRunFlags(
    allocator: std.mem.Allocator,
    run: *RunOptions,
    args: []const []const u8,
) !RunParseStatus {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .help;
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
            if (run.changed_base) |base| {
                allocator.free(base);
                run.changed_base = null;
            }
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

        if (std.mem.startsWith(u8, arg, "--sort=")) {
            run.sort_mode = try types.parseSortMode(arg["--sort=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--sort")) {
            const value = try consumeValue(args, &index, "--sort");
            run.sort_mode = try types.parseSortMode(value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--tree-sort=")) {
            run.tree_sort_mode = try types.parseTreeSortMode(arg["--tree-sort=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--tree-sort")) {
            const value = try consumeValue(args, &index, "--tree-sort");
            run.tree_sort_mode = try types.parseTreeSortMode(value);
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--content-preset=")) {
            run.content_preset = try types.parseContentPreset(arg["--content-preset=".len..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--content-preset")) {
            const value = try consumeValue(args, &index, "--content-preset");
            run.content_preset = try types.parseContentPreset(value);
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

        if (std.mem.startsWith(u8, arg, "--include=")) {
            const value = arg["--include=".len..];
            try run.include_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }
        if (std.mem.eql(u8, arg, "--include")) {
            const value = try consumeValue(args, &index, "--include");
            try run.include_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--exclude=")) {
            const value = arg["--exclude=".len..];
            try run.exclude_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }
        if (std.mem.eql(u8, arg, "--exclude")) {
            const value = try consumeValue(args, &index, "--exclude");
            try run.exclude_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--content-exclude=")) {
            const value = arg["--content-exclude=".len..];
            try run.content_exclude_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }
        if (std.mem.eql(u8, arg, "--content-exclude")) {
            const value = try consumeValue(args, &index, "--content-exclude");
            try run.content_exclude_patterns.append(allocator, try allocator.dupe(u8, value));
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--base=")) {
            const value = arg["--base=".len..];
            if (run.changed_base) |existing| allocator.free(existing);
            run.changed_base = try allocator.dupe(u8, value);
            run.changed_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--base")) {
            const value = try consumeValue(args, &index, "--base");
            if (run.changed_base) |existing| allocator.free(existing);
            run.changed_base = try allocator.dupe(u8, value);
            run.changed_only = true;
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

        if (std.mem.startsWith(u8, arg, "--top-files=")) {
            run.top_files = try parseUsize(arg["--top-files=".len..], "--top-files");
            continue;
        }
        if (std.mem.eql(u8, arg, "--top-files")) {
            const value = try consumeValue(args, &index, "--top-files");
            run.top_files = try parseUsize(value, "--top-files");
            continue;
        }

        if (std.mem.eql(u8, arg, "--strict-json")) {
            run.strict_json = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-strict-json")) {
            run.strict_json = false;
            continue;
        }

        if (std.mem.eql(u8, arg, "--compact")) {
            run.compact = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-compact")) {
            run.compact = false;
            continue;
        }

        std.debug.print("unknown flag: {s}\n", .{arg});
        try printHelp();
        return error.UnknownFlag;
    }

    return .ok;
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
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\Usage:
        \\  ztx [flags]
        \\  ztx ai [flags]
        \\  ztx init [--force] [--dry-run]
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
        \\  --strict-json / --no-strict-json
        \\  --compact / --no-compact
        \\  --sort <name|size|lines>
        \\  --tree-sort <name|lines|bytes>
        \\  --content-preset <none|balanced>
        \\  --content-exclude <glob> (repeatable)
        \\  --top-files <n>
        \\  --profile <review|llm|llm-token|stats|custom>
        \\  --path <dir-or-file> (repeatable)
        \\  --include <glob> (repeatable)
        \\  --exclude <glob> (repeatable)
        \\  --max-depth <n>
        \\  --max-files <n>
        \\  --max-bytes <n>
        \\  --changed (scan only changed tracked/staged files)
        \\  --base <ref> (changed scan relative to merge-base with ref)
        \\  --all (disable changed-only mode)
        \\  --force (for `init`: overwrite existing .ztx.toml)
        \\  --dry-run (for `init`: print config to stdout)
        \\  -h, --help
        \\
        \\Examples:
        \\  ztx
        \\  ztx --stats --no-content
        \\  ztx --color never
        \\  ztx --scan-mode full --path src --path build.zig
        \\  ztx ai
        \\  ztx --format markdown --profile llm
        \\  ztx --format markdown --profile llm-token
        \\  ztx --changed --base origin/main --format json --strict-json
        \\  ztx --tree-sort lines --content-preset balanced --content-exclude ".env*"
        \\  ztx --include "src/**" --exclude "**/*.min.js" --sort size --top-files 50
        \\  ztx init --dry-run
        \\  ztx init --force
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

test "parse ai command uses llm-token profile" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "ai" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expect(run.profile != null);
            try std.testing.expectEqualStrings("llm-token", run.profile.?);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse ai command allows flag overrides" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "ai", "--content", "--format=json" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expect(run.profile != null);
            try std.testing.expectEqualStrings("llm-token", run.profile.?);
            try std.testing.expectEqual(@as(?bool, true), run.show_content);
            try std.testing.expectEqual(types.OutputFormat.json, run.output_format.?);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse supports value flags and repeatable paths" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{
        "ztx",
        "--format=json",
        "--strict-json",
        "--compact",
        "--sort=size",
        "--tree-sort=bytes",
        "--content-preset",
        "none",
        "--color",
        "always",
        "--path",
        "src",
        "--path=build.zig",
        "--include=src/**",
        "--exclude",
        "**/*.bin",
        "--content-exclude",
        ".env*",
        "--content-exclude=README*",
        "--base",
        "origin/main",
        "--max-depth",
        "2",
        "--max-files=20",
        "--max-bytes=1024",
        "--top-files=10",
        "--changed",
    });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(types.OutputFormat.json, run.output_format.?);
            try std.testing.expectEqual(types.ColorMode.always, run.color_mode.?);
            try std.testing.expectEqual(@as(usize, 2), run.paths.items.len);
            try std.testing.expectEqual(@as(usize, 1), run.include_patterns.items.len);
            try std.testing.expectEqual(@as(usize, 1), run.exclude_patterns.items.len);
            try std.testing.expectEqual(@as(usize, 2), run.content_exclude_patterns.items.len);
            try std.testing.expectEqualStrings("origin/main", run.changed_base.?);
            try std.testing.expectEqual(@as(usize, 2), run.max_depth.?);
            try std.testing.expectEqual(@as(usize, 20), run.max_files.?);
            try std.testing.expectEqual(@as(usize, 1024), run.max_bytes.?);
            try std.testing.expectEqual(@as(usize, 10), run.top_files.?);
            try std.testing.expectEqual(types.SortMode.size, run.sort_mode.?);
            try std.testing.expectEqual(types.TreeSortMode.bytes, run.tree_sort_mode.?);
            try std.testing.expectEqual(types.ContentPreset.none, run.content_preset.?);
            try std.testing.expectEqual(@as(?bool, true), run.strict_json);
            try std.testing.expectEqual(@as(?bool, true), run.compact);
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
        .init => |init| {
            try std.testing.expect(!init.force);
            try std.testing.expect(!init.dry_run);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse init command supports force and dry-run flags" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "init", "--force", "--dry-run" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .init => |init| {
            try std.testing.expect(init.force);
            try std.testing.expect(init.dry_run);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parse --all resets changed flags" {
    const allocator = std.testing.allocator;
    var parsed = try parseArgsFrom(allocator, &.{ "ztx", "--base", "origin/main", "--all" });
    defer parsed.deinit(allocator);

    switch (parsed.command) {
        .run => |run| {
            try std.testing.expectEqual(@as(?bool, false), run.changed_only);
            try std.testing.expect(run.changed_base == null);
        },
        else => return error.TestUnexpectedResult,
    }
}

fn parseInitArgs(args: []const []const u8) !InitOptions {
    var options = InitOptions{};

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--force")) {
            options.force = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--dry-run")) {
            options.dry_run = true;
            continue;
        }

        std.debug.print("unknown flag for init command: {s}\n", .{arg});
        try printHelp();
        return error.UnknownFlag;
    }

    return options;
}
