const std = @import("std");

pub fn digitCount(value: usize) usize {
    var n = value;
    var digits: usize = 1;
    while (n >= 10) : (digits += 1) {
        n /= 10;
    }
    return digits;
}

pub fn formatGroupedUsize(buffer: []u8, value: usize) ![]const u8 {
    var raw_buf: [32]u8 = undefined;
    const raw = try std.fmt.bufPrint(&raw_buf, "{d}", .{value});

    var out_index = buffer.len;
    var digit_count: usize = 0;
    var i = raw.len;
    while (i > 0) {
        i -= 1;
        out_index -= 1;
        buffer[out_index] = raw[i];
        digit_count += 1;

        if (i > 0 and digit_count % 3 == 0) {
            out_index -= 1;
            buffer[out_index] = '_';
        }
    }

    return buffer[out_index..];
}

pub fn formatByteSize(buffer: *[32]u8, bytes: usize) ![]const u8 {
    const units = [_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB" };

    if (bytes < 1024) {
        return std.fmt.bufPrint(buffer, "{d}B", .{bytes});
    }

    var value = @as(f64, @floatFromInt(bytes));
    var unit_index: usize = 0;
    while (value >= 1024 and unit_index + 1 < units.len) {
        value /= 1024;
        unit_index += 1;
    }

    return std.fmt.bufPrint(buffer, "{d:.1}{s}", .{ value, units[unit_index] });
}

test "digitCount and grouped format" {
    try std.testing.expectEqual(@as(usize, 1), digitCount(0));
    try std.testing.expectEqual(@as(usize, 4), digitCount(1024));

    var grouped_buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("12_345_678", try formatGroupedUsize(&grouped_buf, 12_345_678));

    var size_buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("999B", try formatByteSize(&size_buf, 999));
}
