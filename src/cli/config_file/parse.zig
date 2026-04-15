const std = @import("std");
const file_types = @import("types.zig");
const keys = @import("keys.zig");
const values = @import("values.zig");

const Section = union(enum) {
    root,
    scan,
    output,
    profile: []const u8,
};

pub fn loadFromCwd(allocator: std.mem.Allocator) !file_types.FileConfig {
    var file = std.fs.cwd().openFile(".ztx.toml", .{}) catch |err| switch (err) {
        error.FileNotFound => return file_types.FileConfig.init(allocator),
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    return parseToml(allocator, content);
}

pub fn parseToml(allocator: std.mem.Allocator, content: []const u8) !file_types.FileConfig {
    var parsed = file_types.FileConfig.init(allocator);
    errdefer parsed.deinit(allocator);

    var section: Section = .root;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trimRight(u8, raw_line, "\r");
        line = values.stripInlineComment(line);
        line = std.mem.trim(u8, line, " \t");

        if (line.len == 0) continue;

        if (line[0] == '[') {
            if (line[line.len - 1] != ']') return error.InvalidConfigSection;
            const section_name = std.mem.trim(u8, line[1 .. line.len - 1], " \t");
            section = try parseSection(allocator, &parsed, section_name);
            continue;
        }

        const sep = std.mem.indexOfScalar(u8, line, '=') orelse return error.InvalidConfigLine;
        const key = std.mem.trim(u8, line[0..sep], " \t");
        const value = std.mem.trim(u8, line[sep + 1 ..], " \t");

        switch (section) {
            .scan => try keys.applyScanKey(allocator, &parsed.scan, key, value),
            .output => try keys.applyOutputKey(allocator, &parsed.output, key, value),
            .profile => |profile_name| {
                const profile_ptr = parsed.profiles.getPtr(profile_name).?;
                if (keys.isScanKey(key)) {
                    try keys.applyScanKey(allocator, &profile_ptr.scan, key, value);
                } else if (keys.isOutputKey(key)) {
                    try keys.applyOutputKey(allocator, &profile_ptr.output, key, value);
                } else {
                    return error.InvalidProfileKey;
                }
            },
            .root => return error.UnscopedConfigKey,
        }
    }

    return parsed;
}

fn parseSection(allocator: std.mem.Allocator, parsed: *file_types.FileConfig, section_name: []const u8) !Section {
    if (std.mem.eql(u8, section_name, "scan")) return .scan;
    if (std.mem.eql(u8, section_name, "output")) return .output;

    const profile_prefix = "profiles.";
    if (std.mem.startsWith(u8, section_name, profile_prefix)) {
        const profile_name = std.mem.trim(u8, section_name[profile_prefix.len..], " \t");
        if (profile_name.len == 0) return error.InvalidProfileName;

        const gop = try parsed.profiles.getOrPut(profile_name);
        if (!gop.found_existing) {
            gop.key_ptr.* = try allocator.dupe(u8, profile_name);
            gop.value_ptr.* = .{};
        }

        return .{ .profile = gop.key_ptr.* };
    }

    return error.InvalidConfigSection;
}
