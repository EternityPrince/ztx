const std = @import("std");
const walker = @import("walker_impl.zig");

const makeTestConfig = walker.makeTestConfig;
const runWalkForTest = walker.runWalkForTest;

test "scan respects max-files limit" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "a.zig", .data = "const a = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "b.zig", .data = "const b = 2;\n" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.max_files = 1;

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.file_limit);
}

test "scan empty directory returns empty result" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.total_files);
    try std.testing.expectEqual(@as(usize, 0), result.total_dirs);
}

test "scan skips oversized content but keeps stats" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const file_size = (1024 * 1024) + 10;
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    @memset(buffer, 'a');
    buffer[file_size - 1] = '\n';

    try tmp.dir.writeFile(.{
        .sub_path = "big.txt",
        .data = buffer,
    });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.show_content = true;
    config.max_content_bytes = 1024 * 1024;

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, file_size), result.total_bytes);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.size_limit);

    switch (result.entries.items[0]) {
        .file => |file| try std.testing.expect(file.content == null),
        .dir => return error.TestUnexpectedResult,
    }
}

test "scan keeps presence files in stats but omits their content" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "README.md", .data = "# hello\n" });
    try tmp.dir.writeFile(.{ .sub_path = "src.zig", .data = "const x = 1;\n" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.show_content = true;
    config.content_preset = .balanced;

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.total_files);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.content_policy);

    var readme_content_is_null = false;
    var zig_content_is_null = true;
    for (result.entries.items) |entry| {
        switch (entry) {
            .file => |file| {
                if (std.mem.eql(u8, file.path, "README.md")) {
                    readme_content_is_null = file.content == null;
                }
                if (std.mem.eql(u8, file.path, "src.zig")) {
                    zig_content_is_null = file.content == null;
                }
            },
            .dir => {},
        }
    }

    try std.testing.expect(readme_content_is_null);
    try std.testing.expect(!zig_content_is_null);
}

test "scan supports custom content exclude patterns" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "notes.md", .data = "note\n" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.show_content = true;
    config.content_preset = .none;
    try config.content_exclude_patterns.append(allocator, try allocator.dupe(u8, "notes.md"));

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.content_policy);

    switch (result.entries.items[0]) {
        .file => |file| try std.testing.expect(file.content == null),
        .dir => return error.TestUnexpectedResult,
    }
}

test "scan full mode skips binary files by content" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "code.zig", .data = "const x = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "blob.bin", .data = "\x00\xff\x01\x02" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.scan_mode = .full;

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expectEqual(@as(usize, 1), result.skipped.binary_or_unsupported);
}

test "scan applies include and exclude patterns" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    try tmp.dir.makePath("pkg");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "const a = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "src/generated.zig", .data = "const b = 2;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "pkg/lib.zig", .data = "const c = 3;\n" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    try config.include_patterns.append(allocator, try allocator.dupe(u8, "src/**/*.zig"));
    try config.exclude_patterns.append(allocator, try allocator.dupe(u8, "src/generated.zig"));

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    switch (result.entries.items[result.entries.items.len - 1]) {
        .file => |file| try std.testing.expectEqualStrings("src/main.zig", file.path),
        .dir => return error.TestUnexpectedResult,
    }
}

test "scan counts symlink as skipped" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "target.zig", .data = "const x = 1;\n" });
    std.posix.symlinkat("target.zig", tmp.dir.fd, "link.zig") catch |err| switch (err) {
        error.AccessDenied, error.OperationNotSupported, error.PermissionDenied => return,
        else => return err,
    };

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.skipped.symlink);
}

test "scan counts permission-denied files as skipped" {
    if (!std.fs.has_executable_bit) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "ok.zig", .data = "const x = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "private.zig", .data = "const y = 2;\n" });

    std.posix.fchmodat(tmp.dir.fd, "private.zig", 0, 0) catch |err| switch (err) {
        error.AccessDenied, error.PermissionDenied, error.OperationNotSupported => return error.SkipZigTest,
        else => return err,
    };
    defer std.posix.fchmodat(tmp.dir.fd, "private.zig", 0o644, 0) catch {};

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expect(result.skipped.permission > 0);
}

test "scan counts depth and byte limits" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("sub/deep");
    try tmp.dir.writeFile(.{ .sub_path = "root.zig", .data = "const a = 1;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sub/inner.zig", .data = "const b = 2;\n" });
    try tmp.dir.writeFile(.{ .sub_path = "sub/deep/more.zig", .data = "const c = 3;\n" });

    var config = try makeTestConfig(allocator);
    defer config.deinit(allocator);
    config.max_depth = 1;
    config.max_bytes = 20;

    var result = try runWalkForTest(allocator, &tmp.dir, &config);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.total_files);
    try std.testing.expect(result.skipped.depth_limit > 0);
    try std.testing.expect(result.skipped.size_limit > 0);
}

test "changed scan reports git unavailable outside repository" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(cwd);

    try std.testing.expectError(error.GitUnavailable, ("walker/changed_paths.zig").collectChangedPathsInCwd(allocator, cwd, null));
}
