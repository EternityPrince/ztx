const std = @import("std");

pub const FileInfo = struct {
    path: []const u8,
    extansion: []const u8,
    line_count: usize,
    byte_size: usize,
    depth_level: usize,
    content: ?[]u8,
};

pub const DirInfo = struct {
    path: []const u8,
    depth_level: usize,
};

// Union to exhausively represent the strucrure
pub const FileDirInfo = union(enum) {
    file: FileInfo,
    dir: DirInfo,
};

pub const ExtansionStat = struct {
    count: usize,
    total_lines: usize,
};

pub const ScanResult = struct {
    entries: std.ArrayList(FileDirInfo),
    ext_stats: std.StringHashMap(ExtansionStat),
    total_lines: usize,
    total_files: usize,
    total_dirs: usize,

    pub fn init(allocator: std.mem.Allocator) ScanResult {
        return .{
            .entries = .empty,
            .ext_stats = std.StringHashMap(ExtansionStat).init(allocator),
            .total_lines = 0,
            .total_files = 0,
            .total_dirs = 0,
        };
    }

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        for (self.entries.items) |entry| {
            switch (entry) {
                .file => |file| {
                    allocator.free(file.path);
                    allocator.free(file.extansion);
                    if (file.content) |content| allocator.free(content);
                },
                .dir => |dir| {
                    allocator.free(dir.path);
                },
            }
        }

        var iter = self.ext_stats.iterator();
        while (iter.next()) |ext| {
            allocator.free(ext.key_ptr.*);
        }

        self.entries.deinit(allocator);
        self.ext_stats.deinit();
    }
};
