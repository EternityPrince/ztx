const impl = @import("walker_helper_impl.zig");
const std = @import("std");

pub const FileReadResult = impl.FileReadResult;

pub fn joinRelativePath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    return impl.joinRelativePath(allocator, prefix, name);
}

pub fn readFileData(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    capture_content: bool,
    file_name: []const u8,
) !FileReadResult {
    return impl.readFileData(allocator, file, capture_content, file_name);
}

pub fn isLikelyBinary(file: *std.fs.File) !bool {
    return impl.isLikelyBinary(file);
}
