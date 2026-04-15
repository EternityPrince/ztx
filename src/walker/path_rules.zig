const std = @import("std");
const policy = @import("../policy/walker_ignore.zig");

pub fn shouldIncludeFile(
    include_patterns: []const []const u8,
    exclude_patterns: []const []const u8,
    rel_path: []const u8,
) bool {
    if (isExcludedPath(exclude_patterns, rel_path)) return false;

    if (include_patterns.len == 0) return true;
    return patternMatchesAny(include_patterns, rel_path);
}

pub fn isExcludedPath(exclude_patterns: []const []const u8, rel_path: []const u8) bool {
    if (exclude_patterns.len == 0) return false;
    return patternMatchesAny(exclude_patterns, rel_path);
}

pub fn pathInScope(path: []const u8, scopes: []const []const u8) bool {
    for (scopes) |scope| {
        if (std.mem.eql(u8, scope, ".")) return true;
        const trimmed_scope = std.mem.trimRight(u8, scope, "/");
        if (trimmed_scope.len == 0) return true;

        if (std.mem.eql(u8, path, trimmed_scope)) return true;
        if (path.len > trimmed_scope.len and
            std.mem.startsWith(u8, path, trimmed_scope) and
            path[trimmed_scope.len] == '/')
        {
            return true;
        }
    }

    return false;
}

pub fn pathDepth(path: []const u8) usize {
    if (path.len == 0) return 0;

    var depth: usize = 0;
    for (path) |char| {
        if (char == '/') depth += 1;
    }

    return depth;
}

fn patternMatchesAny(patterns: []const []const u8, rel_path: []const u8) bool {
    for (patterns) |pattern| {
        if (pattern.len == 0) continue;
        if (policy.matchesPathPattern(pattern, rel_path)) return true;
    }
    return false;
}

test "pathDepth counts nested separators" {
    try std.testing.expectEqual(@as(usize, 0), pathDepth("main.zig"));
    try std.testing.expectEqual(@as(usize, 1), pathDepth("src/main.zig"));
    try std.testing.expectEqual(@as(usize, 3), pathDepth("a/b/c/main.zig"));
}

test "pathInScope supports dot and nested scopes" {
    try std.testing.expect(pathInScope("src/main.zig", &.{"."}));
    try std.testing.expect(pathInScope("src/main.zig", &.{"src"}));
    try std.testing.expect(pathInScope("src/main.zig", &.{"src/main.zig"}));
    try std.testing.expect(!pathInScope("pkg/file.zig", &.{"src"}));
}

test "pathInScope handles long scopes without fixed buffers" {
    const allocator = std.testing.allocator;
    const long_scope = try allocator.alloc(u8, 600);
    defer allocator.free(long_scope);
    @memset(long_scope, 'a');

    const path = try std.fmt.allocPrint(allocator, "{s}/file.zig", .{long_scope});
    defer allocator.free(path);

    try std.testing.expect(pathInScope(path, &.{long_scope}));
}
