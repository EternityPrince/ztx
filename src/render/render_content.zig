const std = @import("std");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;

pub fn printContent(
    writer: anytype,
    files: []const *const model.FileInfo,
    context: RenderContext,
    compact: bool,
) !void {
    const style = context.style;
    var visible_files: usize = 0;
    for (files) |file| {
        if (file.content) |content| {
            if (content.len > 0) visible_files += 1;
        }
    }
    if (visible_files == 0) return;

    try style.write(writer, ansi.section, "FILES\n");

    var printed: usize = 0;
    for (files) |file| {
        const content = file.content orelse continue;
        if (content.len == 0) continue;

        if (printed > 0) try writer.writeAll("\n");

        if (compact) {
            try style.write(writer, ansi.path, "-- ");
            try style.write(writer, ansi.path, file.path);
            try writer.writeAll("\n");
        } else {
            try style.write(writer, ansi.separator, "===== ");
            try style.write(writer, ansi.path, file.path);
            try style.write(writer, ansi.separator, " =====\n");
        }

        try writeNumberedContent(writer, style, content, file.line_count);
        if (!compact) try writer.writeAll("\n");
        printed += 1;
    }
}

fn writeNumberedContent(writer: anytype, style: Style, content: []const u8, line_count: usize) !void {
    if (content.len == 0) return;

    const width = digitCount(@max(line_count, 1));
    var start: usize = 0;
    var line_no: usize = 1;

    while (start < content.len) : (line_no += 1) {
        const next_newline = std.mem.indexOfScalarPos(u8, content, start, '\n');
        const end = next_newline orelse content.len;
        const line = content[start..end];

        try writeLineNumber(writer, style, line_no, width);
        try writer.writeAll(line);
        try writer.writeAll("\n");

        if (next_newline) |idx| {
            start = idx + 1;
        } else {
            break;
        }
    }
}

fn writeLineNumber(writer: anytype, style: Style, line_no: usize, width: usize) !void {
    var buffer: [32]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{d}", .{line_no});
    const pad = width - rendered.len;

    var i: usize = 0;
    while (i < pad) : (i += 1) try writer.writeAll(" ");

    try style.write(writer, ansi.line_number, rendered);
    try style.write(writer, ansi.line_number, " │ ");
}

fn digitCount(value: usize) usize {
    var n = value;
    var digits: usize = 1;

    while (n >= 10) : (digits += 1) {
        n /= 10;
    }

    return digits;
}

test "numbered content handles missing trailing newline" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeNumberedContent(fbs.writer(), .{ .use_color = false }, "a\nb", 2);
    try std.testing.expectEqualStrings("1 │ a\n2 │ b\n", fbs.getWritten());
}

test "printContent skips files without captured body" {
    const allocator = std.testing.allocator;
    const visible_content = try allocator.dupe(u8, "line\n");
    defer allocator.free(visible_content);

    const file_without_content = model.FileInfo{
        .path = "README.md",
        .extension = ".md",
        .line_count = 1,
        .comment_line_count = 0,
        .byte_size = 4,
        .depth_level = 0,
        .content = null,
    };
    const file_with_content = model.FileInfo{
        .path = "src/main.zig",
        .extension = ".zig",
        .line_count = 1,
        .comment_line_count = 0,
        .byte_size = 5,
        .depth_level = 0,
        .content = visible_content,
    };

    const files = [_]*const model.FileInfo{ &file_without_content, &file_with_content };

    var buffer: [2048]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printContent(
        fbs.writer(),
        &files,
        .{ .style = .{ .use_color = false } },
        false,
    );

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "README.md") == null);
    try std.testing.expect(std.mem.indexOf(u8, output, "src/main.zig") != null);
}

test "printContent skips empty file bodies" {
    const empty_content = "";
    const empty_file = model.FileInfo{
        .path = "empty.txt",
        .extension = ".txt",
        .line_count = 0,
        .comment_line_count = 0,
        .byte_size = 0,
        .depth_level = 0,
        .content = empty_content,
    };
    const files = [_]*const model.FileInfo{&empty_file};

    var buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try printContent(
        fbs.writer(),
        &files,
        .{ .style = .{ .use_color = false } },
        false,
    );

    try std.testing.expectEqualStrings("", fbs.getWritten());
}
