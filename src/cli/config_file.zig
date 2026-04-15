const impl = @import("config_file_impl.zig");
const std = @import("std");

pub const ScanPatch = impl.ScanPatch;
pub const OutputPatch = impl.OutputPatch;
pub const ProfilePatch = impl.ProfilePatch;
pub const FileConfig = impl.FileConfig;
pub const WriteStatus = impl.WriteStatus;

pub fn loadFromCwd(allocator: std.mem.Allocator) !FileConfig {
    return impl.loadFromCwd(allocator);
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !FileConfig {
    return impl.parseToml(allocator, content);
}

pub fn writeDefaultToCwd() !void {
    return impl.writeDefaultToCwd();
}

pub fn writeDefaultToCwdWithForce(force: bool) !WriteStatus {
    return impl.writeDefaultToCwdWithForce(force);
}

pub fn defaultTemplate() []const u8 {
    return impl.defaultTemplate();
}
