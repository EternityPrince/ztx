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
