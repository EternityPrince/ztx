const std = @import("std");
const model = @import("../model.zig");
const cli = @import("../cli/config.zig");

pub const FilePtr = *const model.FileInfo;

pub const ExtRow = struct {
    ext: []const u8,
    stat: model.ExtensionStat,
};

pub fn collectSortedExtRows(allocator: std.mem.Allocator, result: *const model.ScanResult) !std.ArrayList(ExtRow) {
    var rows = std.ArrayList(ExtRow).empty;
    errdefer rows.deinit(allocator);

    var iterator = result.ext_stats.iterator();
    while (iterator.next()) |entry| {
        try rows.append(allocator, .{ .ext = entry.key_ptr.*, .stat = entry.value_ptr.* });
    }

    std.mem.sort(ExtRow, rows.items, {}, extRowLessThan);
    return rows;
}

pub fn collectSortedFiles(
    allocator: std.mem.Allocator,
    result: *const model.ScanResult,
    sort_mode: cli.SortMode,
    top_files: ?usize,
) !std.ArrayList(FilePtr) {
    var files = std.ArrayList(FilePtr).empty;
    errdefer files.deinit(allocator);

    for (result.entries.items) |*entry| {
        switch (entry.*) {
            .file => |*file| try files.append(allocator, file),
            .dir => {},
        }
    }

    switch (sort_mode) {
        .name => std.mem.sort(FilePtr, files.items, {}, fileLessByName),
        .size => std.mem.sort(FilePtr, files.items, {}, fileLessBySize),
        .lines => std.mem.sort(FilePtr, files.items, {}, fileLessByLines),
    }

    if (top_files) |limit| {
        if (limit < files.items.len) {
            files.shrinkAndFree(allocator, limit);
        }
    }

    return files;
}

pub fn sharePercent(part: usize, total: usize) f64 {
    if (total == 0) return 0;
    return @as(f64, @floatFromInt(part)) * 100.0 / @as(f64, @floatFromInt(total));
}

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.print("{f}", .{std.json.fmt(value, .{})});
}

fn fileLessByName(_: void, left: FilePtr, right: FilePtr) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn fileLessBySize(_: void, left: FilePtr, right: FilePtr) bool {
    if (left.byte_size != right.byte_size) return left.byte_size > right.byte_size;
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn fileLessByLines(_: void, left: FilePtr, right: FilePtr) bool {
    if (left.line_count != right.line_count) return left.line_count > right.line_count;
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn extRowLessThan(_: void, left: ExtRow, right: ExtRow) bool {
    if (left.stat.count != right.stat.count) return left.stat.count > right.stat.count;
    if (left.stat.total_lines != right.stat.total_lines) return left.stat.total_lines > right.stat.total_lines;
    return std.mem.order(u8, left.ext, right.ext) == .lt;
}
