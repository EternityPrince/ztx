const std = @import("std");
const file_types = @import("config_file/types.zig");
const parser = @import("config_file/parse.zig");
const template = @import("config_file/template.zig");

pub const ScanPatch = file_types.ScanPatch;
pub const OutputPatch = file_types.OutputPatch;
pub const ProfilePatch = file_types.ProfilePatch;
pub const FileConfig = file_types.FileConfig;
pub const WriteStatus = template.WriteStatus;

pub fn loadFromCwd(allocator: std.mem.Allocator) !FileConfig {
    return parser.loadFromCwd(allocator);
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !FileConfig {
    return parser.parseToml(allocator, content);
}

pub fn writeDefaultToCwd() !void {
    return template.writeDefaultToCwd();
}

pub fn writeDefaultToCwdWithForce(force: bool) !WriteStatus {
    return template.writeDefaultToCwdWithForce(force);
}

pub fn defaultTemplate() []const u8 {
    return template.defaultTemplate();
}

pub fn writeDefaultToDir(dir: *std.fs.Dir, force: bool) !WriteStatus {
    return template.writeDefaultToDir(dir, force);
}

test {
    _ = @import("config_file_impl_test.zig");
}
