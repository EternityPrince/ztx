const std = @import("std");
const parse = @import("parse.zig");
const types = @import("types.zig");
const config_file = @import("config_file.zig");

pub const ScanMode = types.ScanMode;
pub const ColorMode = types.ColorMode;
pub const OutputFormat = types.OutputFormat;

const default_max_content_bytes: usize = 1024 * 1024;

pub const Config = struct {
    show_content: bool,
    show_tree: bool,
    show_stats: bool,
    use_color: bool,
    color_mode: ColorMode,
    scan_mode: ScanMode,
    output_format: OutputFormat,
    paths: std.ArrayList([]const u8),
    max_depth: ?usize,
    max_files: ?usize,
    max_bytes: ?usize,
    max_content_bytes: usize,
    changed_only: bool,
    profile_name: ?[]u8,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        for (self.paths.items) |path| allocator.free(path);
        self.paths.deinit(allocator);

        if (self.profile_name) |name| allocator.free(name);
    }

    pub fn fromRunOptions(allocator: std.mem.Allocator, options: parse.RunOptions) !Config {
        var config = try defaultConfig(allocator);
        errdefer config.deinit(allocator);

        var file_config = try config_file.loadFromCwd(allocator);
        defer file_config.deinit(allocator);

        try applyScanPatch(allocator, &config, file_config.scan);
        applyOutputPatch(&config, file_config.output);

        if (options.profile) |profile_name| {
            try applyProfile(allocator, &config, profile_name, &file_config);
        }

        try applyCliOverrides(allocator, &config, options);

        if (config.paths.items.len == 0) {
            try config.paths.append(allocator, try allocator.dupe(u8, "."));
        }

        config.use_color = detectColorMode(config.color_mode, config.output_format);

        try config.validate();
        return config;
    }

    pub fn validate(self: Config) !void {
        if (!self.show_content and !self.show_tree and !self.show_stats) {
            return error.EmptyOutput;
        }
    }
};

pub fn initConfigFile() !void {
    try config_file.writeDefaultToCwd();
}

fn defaultConfig(allocator: std.mem.Allocator) !Config {
    var paths = std.ArrayList([]const u8).empty;
    errdefer paths.deinit(allocator);

    try paths.append(allocator, try allocator.dupe(u8, "."));

    return .{
        .show_content = true,
        .show_tree = true,
        .show_stats = true,
        .use_color = detectColorMode(.auto, .text),
        .color_mode = .auto,
        .scan_mode = .default,
        .output_format = .text,
        .paths = paths,
        .max_depth = null,
        .max_files = null,
        .max_bytes = null,
        .max_content_bytes = default_max_content_bytes,
        .changed_only = false,
        .profile_name = null,
    };
}

fn applyScanPatch(allocator: std.mem.Allocator, config: *Config, patch: config_file.ScanPatch) !void {
    if (patch.scan_mode) |scan_mode| config.scan_mode = scan_mode;
    if (patch.has_paths) try replacePaths(allocator, config, patch.paths.items);
    if (patch.max_depth) |max_depth| config.max_depth = max_depth;
    if (patch.max_files) |max_files| config.max_files = max_files;
    if (patch.max_bytes) |max_bytes| config.max_bytes = max_bytes;
    if (patch.changed_only) |changed_only| config.changed_only = changed_only;
}

fn applyOutputPatch(config: *Config, patch: config_file.OutputPatch) void {
    if (patch.show_tree) |show_tree| config.show_tree = show_tree;
    if (patch.show_content) |show_content| config.show_content = show_content;
    if (patch.show_stats) |show_stats| config.show_stats = show_stats;
    if (patch.color_mode) |color_mode| config.color_mode = color_mode;
    if (patch.output_format) |output_format| config.output_format = output_format;
}

fn applyProfile(
    allocator: std.mem.Allocator,
    config: *Config,
    profile_name: []const u8,
    file_config: *const config_file.FileConfig,
) !void {
    if (std.mem.eql(u8, profile_name, "review")) {
        const profile = builtInReviewProfile();
        try applyScanPatch(allocator, config, profile.scan);
        applyOutputPatch(config, profile.output);
    } else if (std.mem.eql(u8, profile_name, "llm")) {
        const profile = builtInLlmProfile();
        try applyScanPatch(allocator, config, profile.scan);
        applyOutputPatch(config, profile.output);
    } else if (std.mem.eql(u8, profile_name, "stats")) {
        const profile = builtInStatsProfile();
        try applyScanPatch(allocator, config, profile.scan);
        applyOutputPatch(config, profile.output);
    } else if (file_config.getProfile(profile_name)) |custom_profile| {
        try applyScanPatch(allocator, config, custom_profile.scan);
        applyOutputPatch(config, custom_profile.output);
    } else {
        std.debug.print("unknown profile: {s}\n", .{profile_name});
        return error.UnknownProfile;
    }

    if (config.profile_name) |existing| allocator.free(existing);
    config.profile_name = try allocator.dupe(u8, profile_name);
}

fn applyCliOverrides(allocator: std.mem.Allocator, config: *Config, options: parse.RunOptions) !void {
    if (options.show_tree) |show_tree| config.show_tree = show_tree;
    if (options.show_content) |show_content| config.show_content = show_content;
    if (options.show_stats) |show_stats| config.show_stats = show_stats;
    if (options.color_mode) |color_mode| config.color_mode = color_mode;
    if (options.scan_mode) |scan_mode| config.scan_mode = scan_mode;
    if (options.output_format) |output_format| config.output_format = output_format;
    if (options.max_depth) |max_depth| config.max_depth = max_depth;
    if (options.max_files) |max_files| config.max_files = max_files;
    if (options.max_bytes) |max_bytes| config.max_bytes = max_bytes;
    if (options.changed_only) |changed_only| config.changed_only = changed_only;

    if (options.paths.items.len > 0) {
        try replacePaths(allocator, config, options.paths.items);
    }
}

fn replacePaths(allocator: std.mem.Allocator, config: *Config, paths: []const []const u8) !void {
    for (config.paths.items) |path| allocator.free(path);
    config.paths.clearRetainingCapacity();

    if (paths.len == 0) {
        try config.paths.append(allocator, try allocator.dupe(u8, "."));
        return;
    }

    for (paths) |path| {
        const normalized = try normalizePath(allocator, path);
        errdefer allocator.free(normalized);
        try config.paths.append(allocator, normalized);
    }
}

fn normalizePath(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var path = std.mem.trim(u8, raw, " \t");

    while (std.mem.startsWith(u8, path, "./")) {
        path = path[2..];
    }

    path = std.mem.trimRight(u8, path, "/");
    if (path.len == 0) path = ".";

    return allocator.dupe(u8, path);
}

fn detectColorMode(color_mode: ColorMode, output_format: OutputFormat) bool {
    if (output_format != .text) return false;

    return switch (color_mode) {
        .always => true,
        .never => false,
        .auto => std.fs.File.stdout().isTty(),
    };
}

const BuiltInProfile = struct {
    scan: config_file.ScanPatch,
    output: config_file.OutputPatch,
};

fn builtInReviewProfile() BuiltInProfile {
    return .{
        .scan = .{},
        .output = .{
            .show_tree = true,
            .show_content = false,
            .show_stats = true,
            .output_format = .text,
        },
    };
}

fn builtInLlmProfile() BuiltInProfile {
    return .{
        .scan = .{},
        .output = .{
            .show_tree = true,
            .show_content = true,
            .show_stats = true,
            .output_format = .markdown,
            .color_mode = .never,
        },
    };
}

fn builtInStatsProfile() BuiltInProfile {
    return .{
        .scan = .{},
        .output = .{
            .show_tree = false,
            .show_content = false,
            .show_stats = true,
            .output_format = .text,
        },
    };
}

test "defaults can be overridden by profile and cli flags" {
    const allocator = std.testing.allocator;

    var options = parse.RunOptions{};
    defer options.deinit(allocator);

    options.profile = try allocator.dupe(u8, "stats");
    options.show_content = true;
    options.output_format = .json;

    var config = try Config.fromRunOptions(allocator, options);
    defer config.deinit(allocator);

    try std.testing.expect(!config.show_tree);
    try std.testing.expect(config.show_content);
    try std.testing.expect(config.show_stats);
    try std.testing.expectEqual(OutputFormat.json, config.output_format);
}
