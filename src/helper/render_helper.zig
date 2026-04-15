const std = @import("std");

pub fn baseName(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}
