const std = @import("std");

pub const FileReadResult = struct {
    content: ?[]u8,
    line_count: usize,
    comment_line_count: usize,
};

pub fn joinRelativePath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, name);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, name });
}

pub fn readFileData(
    allocator: std.mem.Allocator,
    file: *std.fs.File,
    capture_content: bool,
    file_name: []const u8,
) !FileReadResult {
    try file.seekTo(0);

    var buffer: [4096]u8 = undefined;

    var content = std.ArrayList(u8).empty;
    defer content.deinit(allocator);
    var pending_line = std.ArrayList(u8).empty;
    defer pending_line.deinit(allocator);

    var line_count: usize = 0;
    var comment_line_count: usize = 0;
    var saw_any: bool = false;
    var last_byte: u8 = 0;
    var comment_state = CommentState{
        .rules = commentRulesForFile(file_name),
        .block_kind = .none,
    };

    while (true) {
        const read_bytes = try file.read(buffer[0..]);
        if (read_bytes == 0) break;

        const chunk = buffer[0..read_bytes];
        saw_any = true;
        last_byte = chunk[chunk.len - 1];

        for (chunk) |byte| {
            if (byte == '\n') line_count += 1;
        }

        try appendCommentLines(
            allocator,
            &pending_line,
            chunk,
            &comment_state,
            &comment_line_count,
        );

        if (capture_content == true) try content.appendSlice(allocator, chunk);
    }

    if (saw_any and last_byte != '\n') {
        line_count += 1;
        if (isCommentLine(pending_line.items, &comment_state)) {
            comment_line_count += 1;
        }
    }

    const owned_content = if (capture_content)
        try content.toOwnedSlice(allocator)
    else
        null;

    return .{
        .content = owned_content,
        .line_count = line_count,
        .comment_line_count = comment_line_count,
    };
}

pub fn isLikelyBinary(file: *std.fs.File) !bool {
    try file.seekTo(0);

    var sample: [2048]u8 = undefined;
    const read_bytes = try file.read(sample[0..]);
    try file.seekTo(0);

    if (read_bytes == 0) return false;

    var controls: usize = 0;
    for (sample[0..read_bytes]) |byte| {
        if (byte == 0) return true;

        const is_printable = (byte >= 0x20 and byte <= 0x7e) or byte == '\n' or byte == '\r' or byte == '\t';
        if (!is_printable) controls += 1;
    }

    return controls * 100 / read_bytes > 30;
}

const BlockKind = enum {
    none,
    slash,
    html,
};

const CommentRules = struct {
    slash_line: bool = false,
    hash_line: bool = false,
    dash_line: bool = false,
    slash_block: bool = false,
    html_block: bool = false,
};

const CommentState = struct {
    rules: CommentRules,
    block_kind: BlockKind,
};

fn appendCommentLines(
    allocator: std.mem.Allocator,
    pending_line: *std.ArrayList(u8),
    chunk: []const u8,
    state: *CommentState,
    comment_line_count: *usize,
) !void {
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, chunk, start, '\n')) |newline| {
        try pending_line.appendSlice(allocator, chunk[start..newline]);

        if (isCommentLine(pending_line.items, state)) {
            comment_line_count.* += 1;
        }

        pending_line.clearRetainingCapacity();
        start = newline + 1;
    }

    if (start < chunk.len) {
        try pending_line.appendSlice(allocator, chunk[start..]);
    }
}

fn isCommentLine(raw_line: []const u8, state: *CommentState) bool {
    const line = std.mem.trimRight(u8, raw_line, "\r");
    if (line.len == 0 and state.block_kind == .none) return false;

    var i: usize = 0;
    var in_single_quote = false;
    var in_double_quote = false;
    var escaped = false;
    var has_comment = false;

    while (i < line.len) {
        if (state.block_kind != .none) {
            has_comment = true;
            const end_token = switch (state.block_kind) {
                .none => unreachable,
                .slash => "*/",
                .html => "-->",
            };

            if (std.mem.startsWith(u8, line[i..], end_token)) {
                state.block_kind = .none;
                i += end_token.len;
                continue;
            }

            i += 1;
            continue;
        }

        const char = line[i];
        if (escaped) {
            escaped = false;
            i += 1;
            continue;
        }

        if ((in_single_quote or in_double_quote) and char == '\\') {
            escaped = true;
            i += 1;
            continue;
        }

        if (!in_double_quote and char == '\'') {
            in_single_quote = !in_single_quote;
            i += 1;
            continue;
        }

        if (!in_single_quote and char == '"') {
            in_double_quote = !in_double_quote;
            i += 1;
            continue;
        }

        if (in_single_quote or in_double_quote) {
            i += 1;
            continue;
        }

        if (state.rules.slash_line and std.mem.startsWith(u8, line[i..], "//")) {
            return true;
        }

        if (state.rules.hash_line and char == '#') {
            return true;
        }

        if (state.rules.dash_line and std.mem.startsWith(u8, line[i..], "--")) {
            return true;
        }

        if (state.rules.slash_block and std.mem.startsWith(u8, line[i..], "/*")) {
            has_comment = true;
            i += 2;

            if (std.mem.indexOfPos(u8, line, i, "*/")) |end_pos| {
                i = end_pos + 2;
                continue;
            }

            state.block_kind = .slash;
            break;
        }

        if (state.rules.html_block and std.mem.startsWith(u8, line[i..], "<!--")) {
            has_comment = true;
            i += 4;

            if (std.mem.indexOfPos(u8, line, i, "-->")) |end_pos| {
                i = end_pos + 3;
                continue;
            }

            state.block_kind = .html;
            break;
        }

        i += 1;
    }

    return has_comment;
}

fn commentRulesForFile(file_name: []const u8) CommentRules {
    const ext = std.fs.path.extension(file_name);

    var rules = CommentRules{};

    if (matchesAnyExt(ext, &.{
        ".zig", ".c",  ".h",    ".cpp", ".hpp",  ".cc", ".hh",
        ".go",  ".rs", ".js",   ".ts",  ".java", ".kt", ".swift",
        ".php", ".cs", ".scss",
    })) {
        rules.slash_line = true;
        rules.slash_block = true;
    }

    if (matchesAnyExt(ext, &.{".css"})) {
        rules.slash_block = true;
    }

    if (matchesAnyExt(ext, &.{ ".sql", ".lua" })) {
        rules.dash_line = true;
        rules.slash_block = true;
    }

    if (matchesAnyExt(ext, &.{
        ".py",   ".rb",  ".sh",   ".bash", ".zsh", ".yaml", ".yml",
        ".toml", ".ini", ".conf",
    }) or std.mem.eql(u8, file_name, ".env") or std.mem.startsWith(u8, file_name, ".env.")) {
        rules.hash_line = true;
    }

    if (matchesAnyExt(ext, &.{ ".html", ".xml", ".md" })) {
        rules.html_block = true;
    }

    return rules;
}

fn matchesAnyExt(ext: []const u8, comptime values: []const []const u8) bool {
    inline for (values) |value| {
        if (std.mem.eql(u8, ext, value)) return true;
    }
    return false;
}

test {
    _ = @import("walker_helper_impl_test.zig");
}
