const std = @import("std");

pub fn printFileBody(writer: anytype, path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;

    while (true) {
        const read_bytes = try file.read(buffer[0..]);
        if (read_bytes == 0) return;

        try writer.writeAll(buffer[0..read_bytes]);
    }
}

pub fn printIndent(writer: anytype, depth_level: usize) !void {
    var i: u8 = 0;
    while (i < depth_level) : (i += 1) {
        try writer.writeAll("  ");
    }
}

pub fn baseName(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}
