const std = @import("std");
const types = @import("../types.zig");

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
