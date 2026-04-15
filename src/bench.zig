const std = @import("std");

const cli = @import("cli/config.zig");
const walker = @import("walker.zig");

const Scenario = struct {
    name: []const u8,
    files: usize,
    dirs: usize,
    lines_per_file: usize,
    mode: Mode = .full,
    changed_files: usize = 0,
    staged_files: usize = 0,

    const Mode = enum {
        full,
        changed,
    };
};

const BenchThresholds = struct {
    max_small_ms: ?f64 = null,
    max_large_ms: ?f64 = null,
    max_changed_ms: ?f64 = null,
    max_small_mib: ?f64 = null,
    max_large_mib: ?f64 = null,
    max_changed_mib: ?f64 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) {
            std.debug.print("memory leak detected in bench\n", .{});
        }
    }

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const thresholds = parseThresholdArgs(args[1..]) catch |err| switch (err) {
        error.HelpShown => return,
        else => return err,
    };

    const cwd = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd);

    const scenarios = [_]Scenario{
        .{ .name = "small", .files = 120, .dirs = 6, .lines_per_file = 8 },
        .{ .name = "large", .files = 1600, .dirs = 24, .lines_per_file = 24 },
        .{
            .name = "changed",
            .files = 800,
            .dirs = 16,
            .lines_per_file = 14,
            .mode = .changed,
            .changed_files = 72,
            .staged_files = 24,
        },
    };

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
    var stderr = &stderr_writer.interface;

    try stdout.writeAll("ztx micro-benchmark\n");
    try stdout.writeAll("scenario,files,dirs,lines,elapsed_ms,arena_bytes,arena_mib\n");

    var threshold_failed = false;

    for (scenarios) |scenario| {
        const bench_rel = try std.fmt.allocPrint(allocator, ".zig-cache/bench/{s}", .{scenario.name});
        defer allocator.free(bench_rel);

        const bench_abs = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cwd, bench_rel });
        defer allocator.free(bench_abs);

        const cwd_dir = std.fs.cwd();
        try rebuildFixture(allocator, &cwd_dir, bench_rel, scenario);
        if (scenario.mode == .changed) {
            try prepareChangedRepoFixture(allocator, bench_abs, scenario);
        }

        var config = try makeBenchConfig(allocator);
        defer config.deinit(allocator);
        if (scenario.mode == .changed) {
            config.changed_only = true;
        }

        const previous_cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(previous_cwd);
        defer std.posix.chdir(previous_cwd) catch {};

        try std.posix.chdir(bench_abs);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const bench_allocator = arena.allocator();

        const started_ns = std.time.nanoTimestamp();
        var result = try walker.scan(bench_allocator, &config);
        defer result.deinit(bench_allocator);
        const elapsed_ns = std.time.nanoTimestamp() - started_ns;
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
        const arena_bytes = arena.queryCapacity();
        const arena_mib = bytesToMiB(arena_bytes);

        try stdout.print("{s},{d},{d},{d},{d:.2},{d},{d:.2}\n", .{
            scenario.name,
            result.total_files,
            result.total_dirs,
            result.total_lines,
            elapsed_ms,
            arena_bytes,
            arena_mib,
        });

        threshold_failed = try checkScenarioThresholds(
            stderr,
            scenario.name,
            elapsed_ms,
            arena_mib,
            thresholds,
            threshold_failed,
        );
    }

    try stdout.flush();

    try stderr.flush();
    if (threshold_failed) return error.BenchmarkRegression;
}

fn makeBenchConfig(allocator: std.mem.Allocator) !cli.Config {
    var config = cli.Config{
        .show_content = false,
        .show_tree = false,
        .show_stats = true,
        .use_color = false,
        .color_mode = .never,
        .scan_mode = .default,
        .output_format = .text,
        .paths = std.ArrayList([]const u8).empty,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = 1024 * 1024,
        .changed_only = false,
        .changed_base = null,
        .include_patterns = std.ArrayList([]const u8).empty,
        .exclude_patterns = std.ArrayList([]const u8).empty,
        .strict_json = false,
        .compact = true,
        .sort_mode = .name,
        .tree_sort_mode = .name,
        .content_preset = .balanced,
        .content_exclude_patterns = std.ArrayList([]const u8).empty,
        .top_files = null,
        .profile_name = null,
    };

    try config.paths.append(allocator, try allocator.dupe(u8, "."));
    return config;
}

fn rebuildFixture(allocator: std.mem.Allocator, cwd: *const std.fs.Dir, relative_root: []const u8, scenario: Scenario) !void {
    cwd.deleteTree(relative_root) catch {};

    try cwd.makePath(relative_root);

    var root = try cwd.openDir(relative_root, .{});
    defer root.close();

    var line_template = std.ArrayList(u8).empty;
    defer line_template.deinit(allocator);
    var line_idx: usize = 0;
    while (line_idx < scenario.lines_per_file) : (line_idx += 1) {
        try line_template.writer(allocator).print("const line_{d} = {d};\n", .{ line_idx, line_idx });
    }

    var i: usize = 0;
    while (i < scenario.files) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(allocator, "d{d}", .{i % scenario.dirs});
        defer allocator.free(dir_name);

        try root.makePath(dir_name);

        const file_path = try std.fmt.allocPrint(allocator, "{s}/file_{d}.zig", .{ dir_name, i });
        defer allocator.free(file_path);

        try root.writeFile(.{
            .sub_path = file_path,
            .data = line_template.items,
        });
    }
}

fn prepareChangedRepoFixture(allocator: std.mem.Allocator, repo_abs: []const u8, scenario: Scenario) !void {
    try runGitCommand(allocator, &.{ "git", "init", "-q" }, repo_abs);
    try runGitCommand(allocator, &.{ "git", "config", "user.email", "bench@ztx.local" }, repo_abs);
    try runGitCommand(allocator, &.{ "git", "config", "user.name", "ztx-bench" }, repo_abs);
    try runGitCommand(allocator, &.{ "git", "add", "." }, repo_abs);
    try runGitCommand(allocator, &.{ "git", "commit", "-qm", "baseline" }, repo_abs);

    var repo_dir = try std.fs.openDirAbsolute(repo_abs, .{});
    defer repo_dir.close();

    var i: usize = 0;
    while (i < scenario.changed_files) : (i += 1) {
        const dir_name = try std.fmt.allocPrint(allocator, "d{d}", .{i % scenario.dirs});
        defer allocator.free(dir_name);
        const file_path = try std.fmt.allocPrint(allocator, "{s}/file_{d}.zig", .{ dir_name, i });
        defer allocator.free(file_path);

        const original = try repo_dir.readFileAlloc(allocator, file_path, 2_000_000);
        defer allocator.free(original);

        const updated = try std.fmt.allocPrint(allocator, "{s}const changed_{d} = {d};\n", .{ original, i, i });
        defer allocator.free(updated);
        try repo_dir.writeFile(.{ .sub_path = file_path, .data = updated });

        if (i < scenario.staged_files) {
            const add_cmd = [_][]const u8{ "git", "add", file_path };
            try runGitCommand(allocator, &add_cmd, repo_abs);
        }
    }
}

fn runGitCommand(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    const output = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd,
    }) catch |err| switch (err) {
        error.FileNotFound => return error.GitUnavailable,
        else => return err,
    };
    defer allocator.free(output.stdout);
    defer allocator.free(output.stderr);

    switch (output.term) {
        .Exited => |code| if (code != 0) {
            std.debug.print("git command failed ({s}) in {s}: {s}\n", .{ argv[1], cwd, output.stderr });
            return error.GitUnavailable;
        },
        else => return error.GitUnavailable,
    }
}

fn parseThresholdArgs(args: []const []const u8) !BenchThresholds {
    var thresholds = BenchThresholds{};
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printBenchHelp();
            return error.HelpShown;
        }

        if (std.mem.startsWith(u8, arg, "--max-small-ms=")) {
            thresholds.max_small_ms = try parsePositiveFloat(arg["--max-small-ms=".len..], "--max-small-ms");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-small-ms")) {
            const value = try consumeValue(args, &idx, "--max-small-ms");
            thresholds.max_small_ms = try parsePositiveFloat(value, "--max-small-ms");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-large-ms=")) {
            thresholds.max_large_ms = try parsePositiveFloat(arg["--max-large-ms=".len..], "--max-large-ms");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-large-ms")) {
            const value = try consumeValue(args, &idx, "--max-large-ms");
            thresholds.max_large_ms = try parsePositiveFloat(value, "--max-large-ms");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-small-mib=")) {
            thresholds.max_small_mib = try parsePositiveFloat(arg["--max-small-mib=".len..], "--max-small-mib");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-small-mib")) {
            const value = try consumeValue(args, &idx, "--max-small-mib");
            thresholds.max_small_mib = try parsePositiveFloat(value, "--max-small-mib");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-large-mib=")) {
            thresholds.max_large_mib = try parsePositiveFloat(arg["--max-large-mib=".len..], "--max-large-mib");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-large-mib")) {
            const value = try consumeValue(args, &idx, "--max-large-mib");
            thresholds.max_large_mib = try parsePositiveFloat(value, "--max-large-mib");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-changed-ms=")) {
            thresholds.max_changed_ms = try parsePositiveFloat(arg["--max-changed-ms=".len..], "--max-changed-ms");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-changed-ms")) {
            const value = try consumeValue(args, &idx, "--max-changed-ms");
            thresholds.max_changed_ms = try parsePositiveFloat(value, "--max-changed-ms");
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--max-changed-mib=")) {
            thresholds.max_changed_mib = try parsePositiveFloat(arg["--max-changed-mib=".len..], "--max-changed-mib");
            continue;
        }
        if (std.mem.eql(u8, arg, "--max-changed-mib")) {
            const value = try consumeValue(args, &idx, "--max-changed-mib");
            thresholds.max_changed_mib = try parsePositiveFloat(value, "--max-changed-mib");
            continue;
        }

        std.debug.print("unknown bench flag: {s}\n", .{arg});
        try printBenchHelp();
        return error.UnknownFlag;
    }

    return thresholds;
}

fn consumeValue(args: []const []const u8, idx: *usize, flag_name: []const u8) ![]const u8 {
    idx.* += 1;
    if (idx.* >= args.len) {
        std.debug.print("missing value for {s}\n", .{flag_name});
        return error.MissingValue;
    }

    const value = args[idx.*];
    if (value.len > 0 and value[0] == '-') {
        std.debug.print("missing value for {s}\n", .{flag_name});
        return error.MissingValue;
    }
    return value;
}

fn parsePositiveFloat(raw: []const u8, flag_name: []const u8) !f64 {
    const parsed = std.fmt.parseFloat(f64, raw) catch {
        std.debug.print("invalid numeric value for {s}: {s}\n", .{ flag_name, raw });
        return error.InvalidNumber;
    };
    if (parsed <= 0 or !std.math.isFinite(parsed)) {
        std.debug.print("value for {s} must be positive and finite: {s}\n", .{ flag_name, raw });
        return error.InvalidNumber;
    }
    return parsed;
}

fn bytesToMiB(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
}

fn checkScenarioThresholds(
    stderr: anytype,
    scenario_name: []const u8,
    elapsed_ms: f64,
    arena_mib: f64,
    thresholds: BenchThresholds,
    failed_so_far: bool,
) !bool {
    var failed = failed_so_far;
    const max_ms = if (std.mem.eql(u8, scenario_name, "small"))
        thresholds.max_small_ms
    else if (std.mem.eql(u8, scenario_name, "large"))
        thresholds.max_large_ms
    else if (std.mem.eql(u8, scenario_name, "changed"))
        thresholds.max_changed_ms
    else
        null;
    const max_mib = if (std.mem.eql(u8, scenario_name, "small"))
        thresholds.max_small_mib
    else if (std.mem.eql(u8, scenario_name, "large"))
        thresholds.max_large_mib
    else if (std.mem.eql(u8, scenario_name, "changed"))
        thresholds.max_changed_mib
    else
        null;

    if (max_ms) |limit_ms| {
        if (elapsed_ms > limit_ms) {
            try stderr.print(
                "bench regression: scenario={s} elapsed_ms={d:.2} exceeds limit={d:.2}\n",
                .{ scenario_name, elapsed_ms, limit_ms },
            );
            failed = true;
        }
    }

    if (max_mib) |limit_mib| {
        if (arena_mib > limit_mib) {
            try stderr.print(
                "bench regression: scenario={s} arena_mib={d:.2} exceeds limit={d:.2}\n",
                .{ scenario_name, arena_mib, limit_mib },
            );
            failed = true;
        }
    }

    return failed;
}

fn printBenchHelp() !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\Usage:
        \\  ztx-bench [flags]
        \\
        \\Flags:
        \\  --max-small-ms <value>    fail if small scenario exceeds this time
        \\  --max-large-ms <value>    fail if large scenario exceeds this time
        \\  --max-changed-ms <value>  fail if changed scenario exceeds this time
        \\  --max-small-mib <value>   fail if small scenario exceeds this arena memory
        \\  --max-large-mib <value>   fail if large scenario exceeds this arena memory
        \\  --max-changed-mib <value> fail if changed scenario exceeds this arena memory
        \\  -h, --help
        \\
        \\Examples:
        \\  ztx-bench
        \\  ztx-bench --max-small-ms 50 --max-large-ms 350 --max-changed-ms 120 --max-small-mib 32 --max-large-mib 128 --max-changed-mib 48
        \\
    );
    try stdout.flush();
}

test "parse threshold args supports equals and spaced values" {
    const thresholds = try parseThresholdArgs(&.{
        "--max-small-ms=12.5",
        "--max-large-ms",
        "45.5",
        "--max-changed-ms",
        "9.25",
        "--max-small-mib",
        "3.25",
        "--max-large-mib=9.75",
        "--max-changed-mib=7.5",
    });

    try std.testing.expectEqual(@as(?f64, 12.5), thresholds.max_small_ms);
    try std.testing.expectEqual(@as(?f64, 45.5), thresholds.max_large_ms);
    try std.testing.expectEqual(@as(?f64, 9.25), thresholds.max_changed_ms);
    try std.testing.expectEqual(@as(?f64, 3.25), thresholds.max_small_mib);
    try std.testing.expectEqual(@as(?f64, 9.75), thresholds.max_large_mib);
    try std.testing.expectEqual(@as(?f64, 7.5), thresholds.max_changed_mib);
}

test "check thresholds flags regressions and emits details" {
    var output: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&output);

    const failed = try checkScenarioThresholds(
        fbs.writer(),
        "small",
        10.0,
        5.0,
        .{
            .max_small_ms = 8.0,
            .max_small_mib = 4.0,
        },
        false,
    );

    try std.testing.expect(failed);
    const written = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, written, "elapsed_ms") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "arena_mib") != null);
}
