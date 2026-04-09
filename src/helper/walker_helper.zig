const std = @import("std");

pub fn shouldSkip(name: []const u8) bool {
    // TODO add there parse from .gitignore such a parseGit() []const u8 {...}
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-out");
}

pub fn joinRelativePath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, name });
}

pub fn countLinesInFile(allocator: std.mem.Allocator, file: *std.fs.File) !usize {
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
