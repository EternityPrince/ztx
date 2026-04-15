const std = @import("std");

pub fn parseBool(raw: []const u8) !bool {
    if (std.mem.eql(u8, raw, "true")) return true;
    if (std.mem.eql(u8, raw, "false")) return false;
    return error.InvalidBoolean;
}

pub fn parseUsize(raw: []const u8) !usize {
    return std.fmt.parseInt(usize, raw, 10) catch error.InvalidInteger;
}

pub fn parseString(raw: []const u8) ![]const u8 {
    if (raw.len < 2) return error.InvalidString;
    if (raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidString;
    return raw[1 .. raw.len - 1];
}

pub fn parseStringArray(allocator: std.mem.Allocator, raw: []const u8) !std.ArrayList([]const u8) {
    if (raw.len < 2 or raw[0] != '[' or raw[raw.len - 1] != ']') return error.InvalidArray;

    var result = std.ArrayList([]const u8).empty;
    errdefer {
        for (result.items) |value| allocator.free(value);
        result.deinit(allocator);
    }

    const inner = std.mem.trim(u8, raw[1 .. raw.len - 1], " \t");
    if (inner.len == 0) return result;

    var cursor: usize = 0;
    while (cursor < inner.len) {
        while (cursor < inner.len and (inner[cursor] == ' ' or inner[cursor] == '\t' or inner[cursor] == ',')) : (cursor += 1) {}
        if (cursor >= inner.len) break;

        if (inner[cursor] != '"') return error.InvalidArray;
        cursor += 1;
        const start = cursor;

        while (cursor < inner.len and inner[cursor] != '"') : (cursor += 1) {}
        if (cursor >= inner.len) return error.InvalidArray;

        const value = inner[start..cursor];
        try result.append(allocator, try allocator.dupe(u8, value));
        cursor += 1;
    }

    return result;
}

pub fn stripInlineComment(line: []const u8) []const u8 {
    var in_string = false;
    var escape = false;

    for (line, 0..) |char, idx| {
        if (escape) {
            escape = false;
            continue;
        }

        if (char == '\\') {
            escape = true;
            continue;
        }

        if (char == '"') {
            in_string = !in_string;
            continue;
        }

        if (!in_string and char == '#') {
            return line[0..idx];
        }
    }

    return line;
}
