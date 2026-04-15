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

pub fn parseArgsFrom(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
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
            run.profile = try allocator.dupe(u8, "llm");
            run.show_stats = false;
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

        if (try applyToggleFlag(allocator, run, arg)) continue;
        if (try applyValueFlag(allocator, run, args, &index, arg)) continue;

        std.debug.print("unknown flag: {s}\n", .{arg});
        try printHelp();
        return error.UnknownFlag;
    }

    return .ok;
}

const ToggleKind = enum {
    tree_true,
    tree_false,
    content_true,
    content_false,
    stats_true,
    stats_false,
    color_never,
    full_scan,
    changed_true,
    changed_all,
    strict_json_true,
    strict_json_false,
    compact_true,
    compact_false,
};

const ToggleSpec = struct {
    flag: []const u8,
    kind: ToggleKind,
};

const toggle_specs = [_]ToggleSpec{
    .{ .flag = "--tree", .kind = .tree_true },
    .{ .flag = "--no-tree", .kind = .tree_false },
    .{ .flag = "-no-tree", .kind = .tree_false },
    .{ .flag = "--content", .kind = .content_true },
    .{ .flag = "--no-content", .kind = .content_false },
    .{ .flag = "-no-content", .kind = .content_false },
    .{ .flag = "--stats", .kind = .stats_true },
    .{ .flag = "--no-stats", .kind = .stats_false },
    .{ .flag = "-no-stats", .kind = .stats_false },
    .{ .flag = "-no-color", .kind = .color_never },
    .{ .flag = "-full", .kind = .full_scan },
    .{ .flag = "--changed", .kind = .changed_true },
    .{ .flag = "--all", .kind = .changed_all },
    .{ .flag = "--strict-json", .kind = .strict_json_true },
    .{ .flag = "--no-strict-json", .kind = .strict_json_false },
    .{ .flag = "--compact", .kind = .compact_true },
    .{ .flag = "--no-compact", .kind = .compact_false },
};

fn applyToggleFlag(allocator: std.mem.Allocator, run: *RunOptions, arg: []const u8) !bool {
    for (toggle_specs) |spec| {
        if (!std.mem.eql(u8, arg, spec.flag)) continue;
        try applyToggleKind(allocator, run, spec.kind);
        return true;
    }
    return false;
}

fn applyToggleKind(allocator: std.mem.Allocator, run: *RunOptions, kind: ToggleKind) !void {
    switch (kind) {
        .tree_true => run.show_tree = true,
        .tree_false => run.show_tree = false,
        .content_true => run.show_content = true,
        .content_false => run.show_content = false,
        .stats_true => run.show_stats = true,
        .stats_false => run.show_stats = false,
        .color_never => run.color_mode = .never,
        .full_scan => run.scan_mode = .full,
        .changed_true => run.changed_only = true,
        .strict_json_true => run.strict_json = true,
        .strict_json_false => run.strict_json = false,
        .compact_true => run.compact = true,
        .compact_false => run.compact = false,
        .changed_all => {
            run.changed_only = false;
            if (run.changed_base) |base| {
                allocator.free(base);
                run.changed_base = null;
            }
        },
    }
}

const ValueKind = enum {
    color,
    scan_mode,
    format,
    sort,
    tree_sort,
    content_preset,
    profile,
    path,
    include,
    exclude,
    content_exclude,
    base,
    max_depth,
    max_files,
    max_bytes,
    top_files,
};

const ValueSpec = struct {
    flag: []const u8,
    kind: ValueKind,
};

const value_specs = [_]ValueSpec{
    .{ .flag = "--color", .kind = .color },
    .{ .flag = "--scan-mode", .kind = .scan_mode },
    .{ .flag = "--format", .kind = .format },
    .{ .flag = "--sort", .kind = .sort },
    .{ .flag = "--tree-sort", .kind = .tree_sort },
    .{ .flag = "--content-preset", .kind = .content_preset },
    .{ .flag = "--profile", .kind = .profile },
    .{ .flag = "--path", .kind = .path },
    .{ .flag = "--include", .kind = .include },
    .{ .flag = "--exclude", .kind = .exclude },
    .{ .flag = "--content-exclude", .kind = .content_exclude },
    .{ .flag = "--base", .kind = .base },
    .{ .flag = "--max-depth", .kind = .max_depth },
    .{ .flag = "--max-files", .kind = .max_files },
    .{ .flag = "--max-bytes", .kind = .max_bytes },
    .{ .flag = "--top-files", .kind = .top_files },
};

fn applyValueFlag(
    allocator: std.mem.Allocator,
    run: *RunOptions,
    args: []const []const u8,
    index: *usize,
    arg: []const u8,
) !bool {
    for (value_specs) |spec| {
        const match = matchValueArg(arg, spec.flag);
        if (match == .no_match) continue;

        var value: []const u8 = undefined;
        if (match == .next) {
            value = try consumeValue(args, index, spec.flag);
        } else {
            value = match.inline_value;
        }
        try applyValueKind(allocator, run, spec, value);
        return true;
    }
    return false;
}

const ValueMatch = union(enum) {
    no_match,
    next,
    inline_value: []const u8,
};

fn matchValueArg(arg: []const u8, flag: []const u8) ValueMatch {
    if (!std.mem.startsWith(u8, arg, flag)) return .no_match;
    if (arg.len == flag.len) return .next;
    if (arg[flag.len] != '=') return .no_match;
    return .{ .inline_value = arg[flag.len + 1 ..] };
}

fn applyValueKind(allocator: std.mem.Allocator, run: *RunOptions, spec: ValueSpec, value: []const u8) !void {
    switch (spec.kind) {
        .color => run.color_mode = try types.parseColorMode(value),
        .scan_mode => run.scan_mode = try types.parseScanMode(value),
        .format => run.output_format = try types.parseOutputFormat(value),
        .sort => run.sort_mode = try types.parseSortMode(value),
        .tree_sort => run.tree_sort_mode = try types.parseTreeSortMode(value),
        .content_preset => run.content_preset = try types.parseContentPreset(value),
        .profile => {
            if (run.profile) |existing| allocator.free(existing);
            run.profile = try allocator.dupe(u8, value);
        },
        .path => try appendOwnedString(allocator, &run.paths, value),
        .include => try appendOwnedString(allocator, &run.include_patterns, value),
        .exclude => try appendOwnedString(allocator, &run.exclude_patterns, value),
        .content_exclude => try appendOwnedString(allocator, &run.content_exclude_patterns, value),
        .base => {
            if (run.changed_base) |existing| allocator.free(existing);
            run.changed_base = try allocator.dupe(u8, value);
            run.changed_only = true;
        },
        .max_depth => run.max_depth = try parseUsize(value, spec.flag),
        .max_files => run.max_files = try parseUsize(value, spec.flag),
        .max_bytes => run.max_bytes = try parseUsize(value, spec.flag),
        .top_files => run.top_files = try parseUsize(value, spec.flag),
    }
}

fn appendOwnedString(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    try list.append(allocator, try allocator.dupe(u8, value));
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
        \\Default behavior:
        \\  tree output only (equivalent to --tree --no-stats --no-content)
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

test {
    _ = @import("parse_impl_test.zig");
}
