const std = @import("std");
const types = @import("types.zig");

pub const ScanPatch = struct {
    scan_mode: ?types.ScanMode = null,
    has_paths: bool = false,
    paths: std.ArrayList([]const u8) = .empty,
    has_include_patterns: bool = false,
    include_patterns: std.ArrayList([]const u8) = .empty,
    has_exclude_patterns: bool = false,
    exclude_patterns: std.ArrayList([]const u8) = .empty,
    max_depth: ?usize = null,
    max_files: ?usize = null,
    max_bytes: ?usize = null,
    changed_only: ?bool = null,
    changed_base: ?[]const u8 = null,

    pub fn deinit(self: *ScanPatch, allocator: std.mem.Allocator) void {
        if (self.has_paths) {
            for (self.paths.items) |path| allocator.free(path);
            self.paths.deinit(allocator);
            self.has_paths = false;
        }
        if (self.has_include_patterns) {
            for (self.include_patterns.items) |pattern| allocator.free(pattern);
            self.include_patterns.deinit(allocator);
            self.has_include_patterns = false;
        }
        if (self.has_exclude_patterns) {
            for (self.exclude_patterns.items) |pattern| allocator.free(pattern);
            self.exclude_patterns.deinit(allocator);
            self.has_exclude_patterns = false;
        }
        if (self.changed_base) |base| allocator.free(base);
        self.changed_base = null;
    }
};

pub const OutputPatch = struct {
    show_tree: ?bool = null,
    show_content: ?bool = null,
    show_stats: ?bool = null,
    color_mode: ?types.ColorMode = null,
    output_format: ?types.OutputFormat = null,
    strict_json: ?bool = null,
    compact: ?bool = null,
    sort_mode: ?types.SortMode = null,
    tree_sort_mode: ?types.TreeSortMode = null,
    content_preset: ?types.ContentPreset = null,
    has_content_exclude_patterns: bool = false,
    content_exclude_patterns: std.ArrayList([]const u8) = .empty,
    top_files: ?usize = null,

    pub fn deinit(self: *OutputPatch, allocator: std.mem.Allocator) void {
        if (self.has_content_exclude_patterns) {
            for (self.content_exclude_patterns.items) |pattern| allocator.free(pattern);
            self.content_exclude_patterns.deinit(allocator);
            self.has_content_exclude_patterns = false;
        }
    }
};

pub const ProfilePatch = struct {
    scan: ScanPatch = .{},
    output: OutputPatch = .{},

    pub fn deinit(self: *ProfilePatch, allocator: std.mem.Allocator) void {
        self.scan.deinit(allocator);
        self.output.deinit(allocator);
    }
};

pub const FileConfig = struct {
    scan: ScanPatch = .{},
    output: OutputPatch = .{},
    profiles: std.StringHashMap(ProfilePatch),

    pub fn init(allocator: std.mem.Allocator) FileConfig {
        return .{
            .profiles = std.StringHashMap(ProfilePatch).init(allocator),
        };
    }

    pub fn deinit(self: *FileConfig, allocator: std.mem.Allocator) void {
        self.scan.deinit(allocator);
        self.output.deinit(allocator);

        var it = self.profiles.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }

        self.profiles.deinit();
    }

    pub fn getProfile(self: *const FileConfig, name: []const u8) ?ProfilePatch {
        if (self.profiles.get(name)) |profile| return profile;
        return null;
    }
};

const Section = union(enum) {
    root,
    scan,
    output,
    profile: []const u8,
};

pub fn loadFromCwd(allocator: std.mem.Allocator) !FileConfig {
    var file = std.fs.cwd().openFile(".ztx.toml", .{}) catch |err| switch (err) {
        error.FileNotFound => return FileConfig.init(allocator),
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    return parseToml(allocator, content);
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !FileConfig {
    var parsed = FileConfig.init(allocator);
    errdefer parsed.deinit(allocator);

    var section: Section = .root;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trimRight(u8, raw_line, "\r");
        line = stripInlineComment(line);
        line = std.mem.trim(u8, line, " \t");

        if (line.len == 0) continue;

        if (line[0] == '[') {
            if (line[line.len - 1] != ']') return error.InvalidConfigSection;
            const section_name = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            section = try parseSection(allocator, &parsed, section_name);
            continue;
        }

        const sep = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidConfigLine;
        const key = std.mem.trim(u8, line[0..sep], " \t");
        const value = std.mem.trim(u8, line[sep + 1 ..], " \t");

        switch (section) {
            .scan => try applyScanKey(allocator, &parsed.scan, key, value),
            .output => try applyOutputKey(allocator, &parsed.output, key, value),
            .profile => |profile_name| {
                const profile_ptr = parsed.profiles.getPtr(profile_name).?;
                if (isScanKey(key)) {
                    try applyScanKey(allocator, &profile_ptr.scan, key, value);
                } else if (isOutputKey(key)) {
                    try applyOutputKey(allocator, &profile_ptr.output, key, value);
                } else {
                    return error.InvalidProfileKey;
                }
            },
            .root => return error.UnscopedConfigKey,
        }
    }

    return parsed;
}

fn parseSection(allocator: std.mem.Allocator, parsed: *FileConfig, section_name: []const u8) !Section {
    if (std.mem.eql(u8, section_name, "scan")) return .scan;
    if (std.mem.eql(u8, section_name, "output")) return .output;

    const profile_prefix = "profiles.";
    if (std.mem.startsWith(u8, section_name, profile_prefix)) {
        const profile_name = std.mem.trim(u8, section_name[profile_prefix.len..], " \t");
        if (profile_name.len == 0) return error.InvalidProfileName;

        const gop = try parsed.profiles.getOrPut(profile_name);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, profile_name);
            gop.value_ptr.* = .{};
        }

        return .{ .profile = gop.key_ptr.* };
    }

    return error.InvalidConfigSection;
}

fn applyScanKey(allocator: std.mem.Allocator, patch: *ScanPatch, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "mode") or std.mem.eql(u8, key, "scan_mode")) {
        patch.scan_mode = try types.parseScanMode(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "paths")) {
        try replacePaths(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "include")) {
        try replaceIncludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "exclude")) {
        try replaceExcludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "max_depth")) {
        patch.max_depth = try parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "max_files")) {
        patch.max_files = try parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "max_bytes")) {
        patch.max_bytes = try parseUsize(value);
        return;
    }

    if (std.mem.eql(u8, key, "changed")) {
        patch.changed_only = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "changed_base")) {
        if (patch.changed_base) |existing| allocator.free(existing);
        patch.changed_base = try allocator.dupe(u8, try parseString(value));
        patch.changed_only = true;
        return;
    }

    return error.InvalidScanKey;
}

fn applyOutputKey(allocator: std.mem.Allocator, patch: *OutputPatch, key: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, key, "tree")) {
        patch.show_tree = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "content")) {
        patch.show_content = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "stats")) {
        patch.show_stats = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "color")) {
        patch.color_mode = try types.parseColorMode(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "format")) {
        patch.output_format = try types.parseOutputFormat(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "strict_json")) {
        patch.strict_json = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "compact")) {
        patch.compact = try parseBool(value);
        return;
    }

    if (std.mem.eql(u8, key, "sort")) {
        patch.sort_mode = try types.parseSortMode(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "tree_sort")) {
        patch.tree_sort_mode = try types.parseTreeSortMode(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "content_preset")) {
        patch.content_preset = try types.parseContentPreset(try parseString(value));
        return;
    }

    if (std.mem.eql(u8, key, "content_exclude")) {
        try replaceContentExcludes(allocator, patch, value);
        return;
    }

    if (std.mem.eql(u8, key, "top_files")) {
        patch.top_files = try parseUsize(value);
        return;
    }

    return error.InvalidOutputKey;
}

fn replacePaths(allocator: std.mem.Allocator, patch: *ScanPatch, value: []const u8) !void {
    const parsed_paths = try parseStringArray(allocator, value);
    errdefer {
        for (parsed_paths.items) |path| allocator.free(path);
        var mutable_paths = parsed_paths;
        mutable_paths.deinit(allocator);
    }

    patch.deinit(allocator);
    patch.has_paths = true;
    patch.paths = parsed_paths;
}

fn replaceIncludes(allocator: std.mem.Allocator, patch: *ScanPatch, value: []const u8) !void {
    const parsed_patterns = try parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_include_patterns) {
        for (patch.include_patterns.items) |pattern| allocator.free(pattern);
        patch.include_patterns.deinit(allocator);
    }
    patch.has_include_patterns = true;
    patch.include_patterns = parsed_patterns;
}

fn replaceExcludes(allocator: std.mem.Allocator, patch: *ScanPatch, value: []const u8) !void {
    const parsed_patterns = try parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_exclude_patterns) {
        for (patch.exclude_patterns.items) |pattern| allocator.free(pattern);
        patch.exclude_patterns.deinit(allocator);
    }
    patch.has_exclude_patterns = true;
    patch.exclude_patterns = parsed_patterns;
}

fn replaceContentExcludes(allocator: std.mem.Allocator, patch: *OutputPatch, value: []const u8) !void {
    const parsed_patterns = try parseStringArray(allocator, value);
    errdefer {
        for (parsed_patterns.items) |pattern| allocator.free(pattern);
        var mutable_patterns = parsed_patterns;
        mutable_patterns.deinit(allocator);
    }

    if (patch.has_content_exclude_patterns) {
        for (patch.content_exclude_patterns.items) |pattern| allocator.free(pattern);
        patch.content_exclude_patterns.deinit(allocator);
    }
    patch.has_content_exclude_patterns = true;
    patch.content_exclude_patterns = parsed_patterns;
}

fn isScanKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "mode") or
        std.mem.eql(u8, key, "scan_mode") or
        std.mem.eql(u8, key, "paths") or
        std.mem.eql(u8, key, "include") or
        std.mem.eql(u8, key, "exclude") or
        std.mem.eql(u8, key, "max_depth") or
        std.mem.eql(u8, key, "max_files") or
        std.mem.eql(u8, key, "max_bytes") or
        std.mem.eql(u8, key, "changed") or
        std.mem.eql(u8, key, "changed_base");
}

fn isOutputKey(key: []const u8) bool {
    return std.mem.eql(u8, key, "tree") or
        std.mem.eql(u8, key, "content") or
        std.mem.eql(u8, key, "stats") or
        std.mem.eql(u8, key, "color") or
        std.mem.eql(u8, key, "format") or
        std.mem.eql(u8, key, "strict_json") or
        std.mem.eql(u8, key, "compact") or
        std.mem.eql(u8, key, "sort") or
        std.mem.eql(u8, key, "tree_sort") or
        std.mem.eql(u8, key, "content_preset") or
        std.mem.eql(u8, key, "content_exclude") or
        std.mem.eql(u8, key, "top_files");
}

fn parseBool(raw: []const u8) !bool {
    if (std.mem.eql(u8, raw, "true")) return true;
    if (std.mem.eql(u8, raw, "false")) return false;
    return error.InvalidBoolean;
}

fn parseUsize(raw: []const u8) !usize {
    return std.fmt.parseInt(usize, raw, 10) catch error.InvalidInteger;
}

fn parseString(raw: []const u8) ![]const u8 {
    if (raw.len < 2) return error.InvalidString;
    if (raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidString;
    return raw[1 .. raw.len - 1];
}

fn parseStringArray(allocator: std.mem.Allocator, raw: []const u8) !std.ArrayList([]const u8) {
    if (raw.len < 2 or raw[0] != '[' or raw[raw.len - 1] != ']') return error.InvalidArray;

    var result = std.ArrayList([]const u8).empty;
    errdefer {
        for (result.items) |value| allocator.free(value);
        result.deinit(allocator);
    }

    const inner = std.mem.trim(u8, raw[1 .. raw.len - 1], " \t");
    if (inner.len == 0) return result;

    var cursor: usize = 0;
    while (cursor < inner.len) {
        while (cursor < inner.len and (inner[cursor] == ' ' or inner[cursor] == '\t' or inner[cursor] == ',')) : (cursor += 1) {}
        if (cursor >= inner.len) break;

        if (inner[cursor] != '"') return error.InvalidArray;
        cursor += 1;
        const start = cursor;

        while (cursor < inner.len and inner[cursor] != '"') : (cursor += 1) {}
        if (cursor >= inner.len) return error.InvalidArray;

        const value = inner[start..cursor];
        try result.append(allocator, try allocator.dupe(u8, value));
        cursor += 1;
    }

    return result;
}

fn stripInlineComment(line: []const u8) []const u8 {
    var in_string = false;
    var escape = false;

    for (line, 0..) |char, idx| {
        if (escape) {
            escape = false;
            continue;
        }

        if (char == '\\') {
            escape = true;
            continue;
        }

        if (char == '"') {
            in_string = !in_string;
            continue;
        }

        if (!in_string and char == '#') {
            return line[0..idx];
        }
    }

    return line;
}

pub fn writeDefaultToCwd() !void {
    var cwd = std.fs.cwd();
    _ = try writeDefaultToDir(&cwd, false);
}

pub const WriteStatus = enum {
    created,
    overwritten,
};

pub fn writeDefaultToCwdWithForce(force: bool) !WriteStatus {
    var cwd = std.fs.cwd();
    return writeDefaultToDir(&cwd, force);
}

pub fn defaultTemplate() []const u8 {
    return 
    \\# ztx repository config
    \\
    \\[scan]
    \\mode = "default"
    \\paths = ["."]
    \\include = []
    \\exclude = []
    \\max_depth = 12
    \\max_files = 5000
    \\max_bytes = 20000000
    \\changed = false
    \\# changed_base = "origin/main"
    \\
    \\[output]
    \\tree = true
    \\content = false
    \\stats = true
    \\format = "text"
    \\color = "auto"
    \\strict_json = false
    \\compact = false
    \\sort = "name"
    \\tree_sort = "name"
    \\content_preset = "balanced"
    \\content_exclude = []
    \\top_files = 200
    \\
    \\[profiles.review]
    \\tree = true
    \\content = false
    \\stats = true
    \\format = "text"
    \\
    \\[profiles.llm]
    \\tree = true
    \\content = true
    \\stats = true
    \\format = "markdown"
    \\
    \\[profiles.llm-token]
    \\tree = true
    \\content = false
    \\stats = true
    \\format = "markdown"
    \\tree_sort = "lines"
    \\
    \\[profiles.stats]
    \\tree = false
    \\content = false
    \\stats = true
    \\format = "text"
    \\
    ;
}

fn writeDefaultToDir(dir: *std.fs.Dir, force: bool) !WriteStatus {
    var file = if (force)
        try dir.createFile(".ztx.toml", .{ .truncate = true })
    else
        dir.createFile(".ztx.toml", .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                std.debug.print(".ztx.toml already exists\n", .{});
                return error.ConfigAlreadyExists;
            },
            else => return err,
        };
    defer file.close();

    try file.writeAll(defaultTemplate());
    return if (force) .overwritten else .created;
}

test "parseToml reads scan output and profile sections" {
    const allocator = std.testing.allocator;
    var parsed = try parseToml(allocator,
        \\[scan]
        \\mode = "full"
        \\paths = ["src", "build.zig"]
        \\include = ["src/**"]
        \\exclude = ["**/*.bin"]
        \\max_depth = 2
        \\changed = true
        \\changed_base = "origin/main"
        \\
        \\[output]
        \\tree = true
        \\content = false
        \\stats = true
        \\format = "json"
        \\color = "never"
        \\strict_json = true
        \\compact = true
        \\sort = "size"
        \\tree_sort = "lines"
        \\content_preset = "none"
        \\content_exclude = ["README*", ".env*"]
        \\top_files = 50
        \\
        \\[profiles.custom]
        \\content = true
        \\format = "markdown"
        \\tree_sort = "bytes"
        \\
    );
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(types.ScanMode.full, parsed.scan.scan_mode.?);
    try std.testing.expect(parsed.scan.has_paths);
    try std.testing.expectEqual(@as(usize, 2), parsed.scan.paths.items.len);
    try std.testing.expect(parsed.scan.has_include_patterns);
    try std.testing.expect(parsed.scan.has_exclude_patterns);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.include_patterns.items.len);
    try std.testing.expectEqual(@as(usize, 1), parsed.scan.exclude_patterns.items.len);
    try std.testing.expectEqual(@as(?usize, 2), parsed.scan.max_depth);
    try std.testing.expectEqual(@as(?bool, true), parsed.scan.changed_only);
    try std.testing.expectEqualStrings("origin/main", parsed.scan.changed_base.?);

    try std.testing.expectEqual(types.OutputFormat.json, parsed.output.output_format.?);
    try std.testing.expectEqual(types.ColorMode.never, parsed.output.color_mode.?);
    try std.testing.expectEqual(@as(?bool, true), parsed.output.strict_json);
    try std.testing.expectEqual(@as(?bool, true), parsed.output.compact);
    try std.testing.expectEqual(types.SortMode.size, parsed.output.sort_mode.?);
    try std.testing.expectEqual(types.TreeSortMode.lines, parsed.output.tree_sort_mode.?);
    try std.testing.expectEqual(types.ContentPreset.none, parsed.output.content_preset.?);
    try std.testing.expect(parsed.output.has_content_exclude_patterns);
    try std.testing.expectEqual(@as(usize, 2), parsed.output.content_exclude_patterns.items.len);
    try std.testing.expectEqual(@as(?usize, 50), parsed.output.top_files);

    const custom = parsed.getProfile("custom").?;
    try std.testing.expectEqual(@as(?bool, true), custom.output.show_content);
    try std.testing.expectEqual(types.OutputFormat.markdown, custom.output.output_format.?);
    try std.testing.expectEqual(types.TreeSortMode.bytes, custom.output.tree_sort_mode.?);
}

test "writeDefaultToDir supports overwrite mode" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const first = try writeDefaultToDir(&tmp.dir, false);
    try std.testing.expectEqual(WriteStatus.created, first);

    try tmp.dir.writeFile(.{
        .sub_path = ".ztx.toml",
        .data = "legacy=true\n",
    });

    const second = try writeDefaultToDir(&tmp.dir, true);
    try std.testing.expectEqual(WriteStatus.overwritten, second);

    const rendered = try tmp.dir.readFileAlloc(std.testing.allocator, ".ztx.toml", 1_000_000);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(defaultTemplate(), rendered);
}
