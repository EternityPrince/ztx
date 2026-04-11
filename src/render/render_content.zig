const std = @import("std");
const model = @import("../model.zig");
const RenderContext = @import("context.zig").RenderContext;
const ansi = @import("style.zig").ansi;
const Style = @import("style.zig").Style;

pub fn printContent(writer: anytype, result: *const model.ScanResult, context: RenderContext) !void {
    const style = context.style;
    try style.write(writer, ansi.section, "FILES\n");

    for (result.entries.items) |entry| {
        switch (entry) {
            .dir => {},
            .file => |file| {
                try style.write(writer, ansi.separator, "===== ");
                try style.write(writer, ansi.path, file.path);
                try style.write(writer, ansi.separator, " =====\n");

                if (file.content) |content| {
                    try writeNumberedContent(writer, style, content, file.line_count);
                }

                try writer.writeAll("\n");
            },
        }
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

test "numbered content handles empty file" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeNumberedContent(fbs.writer(), .{ .use_color = false }, "", 0);
    try std.testing.expectEqualStrings("", fbs.getWritten());
}

test "numbered content handles single line with trailing newline" {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeNumberedContent(fbs.writer(), .{ .use_color = false }, "hello\n", 1);
    try std.testing.expectEqualStrings("1 │ hello\n", fbs.getWritten());
}
