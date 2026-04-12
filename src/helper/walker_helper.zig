const std = @import("std");

pub const FileReadResult = struct {
    content: ?[]u8,
    line_count: usize,
};

pub fn joinRelativePath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, name });
}

pub fn readFileData(allocator: std.mem.Allocator, file: *std.fs.File, capture_content: bool) !FileReadResult {
    try file.seekTo(0);

    var buffer: [4096]u8 = undefined;

    var content = std.ArrayList(u8).empty;
    defer content.deinit(allocator);

    var line_count: usize = 0;
    var saw_any: bool = false;
    var last_byte: u8 = 0;

    while (true) {
        const read_bytes = try file.read(buffer[0..]);
        if (read_bytes == 0) break;

        const chunk = buffer[0..read_bytes];
        saw_any = true;
        last_byte = chunk[chunk.len - 1];

        for (chunk) |byte| {
            if (byte == '\n') line_count += 1;
        }

        if (capture_content == true) try content.appendSlice(allocator, chunk);
    }

    if (saw_any and last_byte != '\n') line_count += 1;

    const owned_content = if (capture_content)
        try content.toOwnedSlice(allocator)
    else
        null;

    return .{ .content = owned_content, .line_count = line_count };
}

test "joinRelativePath handles root and nested prefixes" {
    const allocator = std.testing.allocator;

    const root_joined = try joinRelativePath(allocator, "", "main.zig");
    defer allocator.free(root_joined);
    try std.testing.expectEqualStrings("main.zig", root_joined);

    const nested_joined = try joinRelativePath(allocator, "src/render", "render.zig");
    defer allocator.free(nested_joined);
    try std.testing.expectEqualStrings("src/render/render.zig", nested_joined);
}

test "readFileData counts lines and returns content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "sample.txt",
        .data = "a\nb",
    });

    var file = try tmp.dir.openFile("sample.txt", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, true);
    defer if (result.content) |content| std.testing.allocator.free(content);

    try std.testing.expectEqual(@as(usize, 2), result.line_count);
    try std.testing.expectEqualStrings("a\nb", result.content.?);
}

test "readFileData can skip content capture" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "sample.txt",
        .data = "line-1\nline-2\n",
    });

    var file = try tmp.dir.openFile("sample.txt", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false);

    try std.testing.expectEqual(@as(usize, 2), result.line_count);
    try std.testing.expect(result.content == null);
}
