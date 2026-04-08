const std = @import("std");

pub const FileInfo = struct {
    path: []const u8,
    extansion: []const u8,
    line_count: usize,
    byte_size: usize,
};

pub const ExtansionStat = struct {
    count: usize,
    total_lines: usize,
};

pub const ScanResult = struct {
    files: std.ArrayList(FileInfo),
    ext_stats: std.StringHashMap(ExtansionStat),
    total_lines: usize,
    total_files: usize,

    pub fn init(allocator: std.mem.Allocator) ScanResult {
        return .{
            .files = .empty,
            .ext_stats = std.StringHashMap(ExtansionStat).init(allocator),
            .total_lines = 0,
            .total_files = 0,
        };
    }

    pub fn deinit(self: *ScanResult, allocator: std.mem.Allocator) void {
        for (self.files.items) |file| {
            allocator.free(file.path);
            allocator.free(file.extansion);
        }

        var iter = self.ext_stats.iterator();
        while (iter.next()) |ext| {
            allocator.free(ext.key_ptr.*);
        }

        self.files.deinit(allocator);
        self.ext_stats.deinit();
    }
};
