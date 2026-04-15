const std = @import("std");
const core = @import("config_file_core.zig");

pub const ScanPatch = core.ScanPatch;
pub const OutputPatch = core.OutputPatch;
pub const ProfilePatch = core.ProfilePatch;
pub const FileConfig = core.FileConfig;
pub const WriteStatus = core.WriteStatus;

pub fn loadFromCwd(allocator: std.mem.Allocator) !FileConfig {
    return core.loadFromCwd(allocator);
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !FileConfig {
    return core.parseToml(allocator, content);
}

pub fn writeDefaultToCwd() !void {
    return core.writeDefaultToCwd();
}

pub fn writeDefaultToCwdWithForce(force: bool) !WriteStatus {
    return core.writeDefaultToCwdWithForce(force);
}

pub fn defaultTemplate() []const u8 {
    return core.defaultTemplate();
}

pub fn writeDefaultToDir(dir: *std.fs.Dir, force: bool) !WriteStatus {
    return core.writeDefaultToDir(dir, force);
}

test {
    _ = @import("config_file_impl_test.zig");
}
