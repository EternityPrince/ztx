const impl = @import("walker_ignore_impl.zig");
const std = @import("std");
const types = @import("../cli/types.zig");

pub const GitIgnore = impl.GitIgnore;
pub const PathSkipReason = impl.PathSkipReason;

pub fn pathSkipReason(
    name: []const u8,
    rel_path: []const u8,
    kind: std.fs.Dir.Entry.Kind,
    gitignore: *const GitIgnore,
) ?PathSkipReason {
    return impl.pathSkipReason(name, rel_path, kind, gitignore);
}

pub fn shouldScanFile(name: []const u8, scan_mode: types.ScanMode) bool {
    return impl.shouldScanFile(name, scan_mode);
}

pub fn matchesPathPattern(pattern: []const u8, rel_path: []const u8) bool {
    return impl.matchesPathPattern(pattern, rel_path);
}
