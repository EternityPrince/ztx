const std = @import("std");
const helper = @import("walker_helper_impl.zig");

const joinRelativePath = helper.joinRelativePath;
const readFileData = helper.readFileData;
const isLikelyBinary = helper.isLikelyBinary;

test "joinRelativePath handles root and nested prefixes" {
    const allocator = std.testing.allocator;

    const root_joined = try joinRelativePath(allocator, "", "main.zig");
    defer allocator.free(root_joined);
    try std.testing.expectEqualStrings("main.zig", root_joined);

    const nested_joined = try joinRelativePath(allocator, "src/render", "render.zig");
    defer allocator.free(nested_joined);
    try std.testing.expectEqualStrings("src/render/render.zig", nested_joined);
}

test "readFileData counts lines and returns content" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "sample.txt",
        .data = "a\nb",
    });

    var file = try tmp.dir.openFile("sample.txt", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, true, "sample.txt");
    defer if (result.content) |content| std.testing.allocator.free(content);

    try std.testing.expectEqual(@as(usize, 2), result.line_count);
    try std.testing.expectEqual(@as(usize, 0), result.comment_line_count);
    try std.testing.expectEqualStrings("a\nb", result.content.?);
}

test "readFileData can skip content capture" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "sample.txt",
        .data = "line-1\nline-2\n",
    });

    var file = try tmp.dir.openFile("sample.txt", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false, "sample.txt");

    try std.testing.expectEqual(@as(usize, 2), result.line_count);
    try std.testing.expectEqual(@as(usize, 0), result.comment_line_count);
    try std.testing.expect(result.content == null);
}

test "readFileData counts slash and block comments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "sample.zig",
        .data =
        \\const a = 1;
        \\// single line
        \\/*
        \\block line
        \\*/
        \\const b = 2;
        \\
        ,
    });

    var file = try tmp.dir.openFile("sample.zig", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false, "sample.zig");
    try std.testing.expectEqual(@as(usize, 6), result.line_count);
    try std.testing.expectEqual(@as(usize, 4), result.comment_line_count);
}

test "readFileData counts hash comments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = ".env.local",
        .data =
        \\# local variables
        \\TOKEN=abc
        \\# trailing
        \\
        ,
    });

    var file = try tmp.dir.openFile(".env.local", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false, ".env.local");
    try std.testing.expectEqual(@as(usize, 3), result.line_count);
    try std.testing.expectEqual(@as(usize, 2), result.comment_line_count);
}

test "readFileData counts html block comments" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "index.html",
        .data =
        \\<!-- top -->
        \\<div>ok</div>
        \\<!--
        \\hidden
        \\-->
        \\
        ,
    });

    var file = try tmp.dir.openFile("index.html", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false, "index.html");
    try std.testing.expectEqual(@as(usize, 5), result.line_count);
    try std.testing.expectEqual(@as(usize, 4), result.comment_line_count);
}

test "readFileData counts inline comments and ignores string literals" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "inline.zig",
        .data =
        \\const url = "https://example.com";
        \\const value = 42; // inline
        \\const marker = "/* not a comment */";
        \\const hash = "# text";
        \\
        ,
    });

    var file = try tmp.dir.openFile("inline.zig", .{});
    defer file.close();

    const result = try readFileData(std.testing.allocator, &file, false, "inline.zig");
    try std.testing.expectEqual(@as(usize, 4), result.line_count);
    try std.testing.expectEqual(@as(usize, 1), result.comment_line_count);
}

test "isLikelyBinary detects text and binary samples" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "text.txt",
        .data = "line-1\nline-2\n",
    });
    try tmp.dir.writeFile(.{
        .sub_path = "bin.bin",
        .data = "\x00\xff\x01\x02DATA",
    });

    var text_file = try tmp.dir.openFile("text.txt", .{});
    defer text_file.close();
    try std.testing.expect(!(try isLikelyBinary(&text_file)));

    var bin_file = try tmp.dir.openFile("bin.bin", .{});
    defer bin_file.close();
    try std.testing.expect(try isLikelyBinary(&bin_file));
}
