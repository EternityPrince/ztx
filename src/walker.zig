const std = @import("std");
const model = @import("model.zig");

pub fn scanCurrentDir(allocator: std.mem.Allocator) !model.ScanResult {
    var result = model.ScanResult.init(allocator);
    errdefer result.deinit(allocator);

    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(".", .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        const path_copy = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(path_copy);

        const ext = std.fs.path.extension(entry.name);
        const ext_value = if (ext.len == 0) "[no extension]" else ext;

        const ext_copy = try allocator.dupe(u8, ext_value);
        errdefer allocator.free(ext_value);

        const file = try dir.openFile(entry.name, .{});
        defer file.close();

        const stat = try file.stat();
        const line_count = try countLinesInFile(allocator, file);

        try result.files.append(allocator, .{
            .path = path_copy,
            .extansion = ext_copy,
            .line_count = line_count,
            .byte_size = stat.size,
        });

        result.total_files += 1;
        result.total_lines += line_count;

        const gop = try result.ext_stats.getOrPut(ext_copy);
        if (!gop.found_existing) {
            const map_key = try allocator.dupe(u8, ext_value);
            errdefer allocator.free(ext_value);

            gop.key_ptr.* = map_key;
            gop.value_ptr.* = .{
                .total_lines = line_count,
                .count = 1,
            };
        } else {
            gop.value_ptr.*.total_lines += line_count;
            gop.value_ptr.*.count += 1;
        }
    }
    return result;
}

fn countLinesInFile(allocator: std.mem.Allocator, file: std.fs.File) !usize {
    try file.seekTo(0);
    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    if (content.len == 0) return 0;

    var count: usize = 0;
    for (content) |byte| {
        if (byte == '\n') count += 1;
    }

    if (content[content.len - 1] != '\n') count += 1;
    return count;
}
