const std = @import("std");
const policy = @import("walker_ignore_impl.zig");

const GitIgnore = policy.GitIgnore;
const PathSkipReason = policy.PathSkipReason;
const pathSkipReason = policy.pathSkipReason;
const shouldScanFile = policy.shouldScanFile;
const matchesPathPattern = policy.matchesPathPattern;

test "gitignore rules support wildcard and negation" {
    const allocator = std.testing.allocator;
    var ignore = try GitIgnore.loadFromContent(allocator,
        \\build/
        \\*.log
        \\!keep.log
        \\src/generated/*
        \\
    );
    defer ignore.deinit(allocator);

    try std.testing.expect(ignore.shouldSkipPath("build", "build", .directory));
    try std.testing.expect(ignore.shouldSkipPath("nested/build", "build", .directory));
    try std.testing.expect(ignore.shouldSkipPath("error.log", "error.log", .file));
    try std.testing.expect(!ignore.shouldSkipPath("keep.log", "keep.log", .file));
    try std.testing.expect(ignore.shouldSkipPath("src/generated/a.zig", "a.zig", .file));
    try std.testing.expect(!ignore.shouldSkipPath("src/other/a.zig", "a.zig", .file));
}

test "pathSkipReason applies built-in and gitignore rules" {
    const allocator = std.testing.allocator;
    var ignore = try GitIgnore.loadFromContent(allocator,
        \\ignored.txt
        \\
    );
    defer ignore.deinit(allocator);

    try std.testing.expectEqual(PathSkipReason.builtin, pathSkipReason(".git", ".git", .directory, &ignore).?);
    try std.testing.expectEqual(PathSkipReason.builtin, pathSkipReason("photo.png", "assets/photo.png", .file, &ignore).?);
    try std.testing.expectEqual(PathSkipReason.gitignore, pathSkipReason("ignored.txt", "ignored.txt", .file, &ignore).?);
    try std.testing.expect(pathSkipReason("main.zig", "src/main.zig", .file, &ignore) == null);
}

test "shouldScanFile obeys scan mode" {
    try std.testing.expect(shouldScanFile("main.zig", .default));
    try std.testing.expect(!shouldScanFile("archive.bin", .default));
    try std.testing.expect(shouldScanFile("archive.bin", .full));
}

test "matchesPathPattern supports basename and path patterns" {
    try std.testing.expect(matchesPathPattern("*.zig", "src/main.zig"));
    try std.testing.expect(matchesPathPattern("src/**/*.zig", "src/render/render.zig"));
    try std.testing.expect(!matchesPathPattern("src/**/*.zig", "pkg/render.zig"));
}
