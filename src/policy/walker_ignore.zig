const std = @import("std");
const types = @import("../cli/types.zig");

const GitIgnoreRule = struct {
    pattern: []const u8,
    negated: bool,
    directory_only: bool,
    anchored: bool,
    has_slash: bool,
};

pub const GitIgnore = struct {
    rules: std.ArrayList(GitIgnoreRule),

    pub fn initEmpty() GitIgnore {
        return .{ .rules = .empty };
    }

    pub fn loadFromCwd(allocator: std.mem.Allocator) !GitIgnore {
        var file = std.fs.cwd().openFile(".gitignore", .{}) catch |err| switch (err) {
            error.FileNotFound => return initEmpty(),
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return loadFromContent(allocator, content);
    }

    pub fn loadFromContent(allocator: std.mem.Allocator, content: []const u8) !GitIgnore {
        var ignore = initEmpty();
        errdefer ignore.deinit(allocator);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            var line = std.mem.trimRight(u8, raw_line, "\r");
            line = std.mem.trim(u8, line, " \t");

            if (line.len == 0) continue;
            if (line[0] == '#') continue;

            var negated = false;
            if (line[0] == '!') {
                negated = true;
                line = line[1..];
            }

            if (line.len == 0) continue;

            var directory_only = false;
            if (std.mem.endsWith(u8, line, "/")) {
                directory_only = true;
                line = std.mem.trimRight(u8, line, "/");
            }

            if (line.len == 0) continue;

            var anchored = false;
            if (line[0] == '/') {
                anchored = true;
                line = line[1..];
            }

            if (line.len == 0) continue;

            if (line[0] == '\\' and line.len > 1 and (line[1] == '#' or line[1] == '!')) {
                line = line[1..];
            }

            const stored_pattern = try allocator.dupe(u8, line);
            errdefer allocator.free(stored_pattern);

            try ignore.rules.append(allocator, .{
                .pattern = stored_pattern,
                .negated = negated,
                .directory_only = directory_only,
                .anchored = anchored,
                .has_slash = std.mem.indexOfScalar(u8, line, '/') != null,
            });
        }

        return ignore;
    }

    pub fn deinit(self: *GitIgnore, allocator: std.mem.Allocator) void {
        for (self.rules.items) |rule| allocator.free(rule.pattern);
        self.rules.deinit(allocator);
    }

    pub fn shouldSkipPath(self: *const GitIgnore, rel_path: []const u8, base_name: []const u8, kind: std.fs.Dir.Entry.Kind) bool {
        var ignored = false;

        for (self.rules.items) |rule| {
            if (ruleMatches(rule, rel_path, base_name, kind)) {
                ignored = !rule.negated;
            }
        }

        return ignored;
    }
};

pub const PathSkipReason = enum {
    builtin,
    gitignore,
};

const ignored_names = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-out",
    ".DS_Store",
};

const ignored_file_extensions = [_][]const u8{
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".pdf",
    ".zip",
    ".tar",
    ".gz",
    ".exe",
    ".class",
    ".o",
    ".a",
    ".so",
    ".dylib",
    ".dll",
};

const default_source_extensions = [_][]const u8{
    ".zig",
    ".c",
    ".h",
    ".cpp",
    ".hpp",
    ".cc",
    ".hh",
    ".go",
    ".rs",
    ".py",
    ".js",
    ".ts",
    ".java",
    ".kt",
    ".swift",
    ".php",
    ".rb",
    ".lua",
    ".cs",
    ".sh",
    ".bash",
    ".zsh",
    ".sql",
    ".html",
    ".css",
    ".scss",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".xml",
    ".md",
    ".txt",
};

pub fn pathSkipReason(
    name: []const u8,
    rel_path: []const u8,
    kind: std.fs.Dir.Entry.Kind,
    gitignore: *const GitIgnore,
) ?PathSkipReason {
    if (matchesIgnoredName(name)) return .builtin;
    if (kind == .file and matchesIgnoredExtension(name)) return .builtin;
    if (gitignore.shouldSkipPath(rel_path, name, kind)) return .gitignore;
    return null;
}

pub fn shouldScanFile(name: []const u8, scan_mode: types.ScanMode) bool {
    return switch (scan_mode) {
        .default => matchesDefaultSources(name),
        .full => true,
    };
}

fn matchesDefaultSources(name: []const u8) bool {
    const extension = std.fs.path.extension(name);

    inline for (default_source_extensions) |ext| {
        if (std.mem.eql(u8, ext, extension)) return true;
    }
    return false;
}

fn matchesIgnoredName(name: []const u8) bool {
    inline for (ignored_names) |ignored| {
        if (std.mem.eql(u8, name, ignored)) return true;
    }
    return false;
}

fn matchesIgnoredExtension(name: []const u8) bool {
    const extension = std.fs.path.extension(name);

    inline for (ignored_file_extensions) |ignored| {
        if (std.mem.eql(u8, extension, ignored)) return true;
    }
    return false;
}

fn ruleMatches(rule: GitIgnoreRule, rel_path: []const u8, base_name: []const u8, kind: std.fs.Dir.Entry.Kind) bool {
    if (rule.directory_only and kind != .directory) return false;

    if (rule.anchored or rule.has_slash) {
        return wildcardMatch(rule.pattern, rel_path, true);
    }

    return wildcardMatch(rule.pattern, base_name, false);
}

fn wildcardMatch(pattern: []const u8, text: []const u8, slash_sensitive: bool) bool {
    if (pattern.len == 0) return text.len == 0;

    const head = pattern[0];
    if (head == '*') {
        var star_count: usize = 1;
        while (star_count < pattern.len and pattern[star_count] == '*') : (star_count += 1) {}

        const rest = pattern[star_count..];
        const can_cross_separator = star_count >= 2;

        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (!can_cross_separator and slash_sensitive and i > 0 and text[i - 1] == '/') break;
            if (wildcardMatch(rest, text[i..], slash_sensitive)) return true;
        }

        return false;
    }

    if (head == '?') {
        if (text.len == 0) return false;
        if (slash_sensitive and text[0] == '/') return false;
        return wildcardMatch(pattern[1..], text[1..], slash_sensitive);
    }

    if (text.len == 0) return false;
    if (head != text[0]) return false;

    return wildcardMatch(pattern[1..], text[1..], slash_sensitive);
}

test "gitignore rules support wildcard and negation" {
    const allocator = std.testing.allocator;
    var ignore = try GitIgnore.loadFromContent(allocator,
        \\build/
        \\*.log
        \\!keep.log
        \\src/generated/*
        \\
    );
    defer ignore.deinit(allocator);

    try std.testing.expect(ignore.shouldSkipPath("build", "build", .directory));
    try std.testing.expect(ignore.shouldSkipPath("nested/build", "build", .directory));
    try std.testing.expect(ignore.shouldSkipPath("error.log", "error.log", .file));
    try std.testing.expect(!ignore.shouldSkipPath("keep.log", "keep.log", .file));
    try std.testing.expect(ignore.shouldSkipPath("src/generated/a.zig", "a.zig", .file));
    try std.testing.expect(!ignore.shouldSkipPath("src/other/a.zig", "a.zig", .file));
}

test "pathSkipReason applies built-in and gitignore rules" {
    const allocator = std.testing.allocator;
    var ignore = try GitIgnore.loadFromContent(allocator,
        \\ignored.txt
        \\
    );
    defer ignore.deinit(allocator);

    try std.testing.expectEqual(PathSkipReason.builtin, pathSkipReason(".git", ".git", .directory, &ignore).?);
    try std.testing.expectEqual(PathSkipReason.builtin, pathSkipReason("photo.png", "assets/photo.png", .file, &ignore).?);
    try std.testing.expectEqual(PathSkipReason.gitignore, pathSkipReason("ignored.txt", "ignored.txt", .file, &ignore).?);
    try std.testing.expect(pathSkipReason("main.zig", "src/main.zig", .file, &ignore) == null);
}

test "shouldScanFile obeys scan mode" {
    try std.testing.expect(shouldScanFile("main.zig", .default));
    try std.testing.expect(!shouldScanFile("archive.bin", .default));
    try std.testing.expect(shouldScanFile("archive.bin", .full));
}
