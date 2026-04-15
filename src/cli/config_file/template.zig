const std = @import("std");

pub const WriteStatus = enum {
    created,
    overwritten,
};

pub fn writeDefaultToCwd() !void {
    var cwd = std.fs.cwd();
    _ = try writeDefaultToDir(&cwd, false);
}

pub fn writeDefaultToCwdWithForce(force: bool) !WriteStatus {
    var cwd = std.fs.cwd();
    return writeDefaultToDir(&cwd, force);
}

pub fn defaultTemplate() []const u8 {
    return 
    \\# ztx repository config
    \\
    \\[scan]
    \\mode = "default"
    \\paths = ["."]
    \\include = []
    \\exclude = []
    \\max_depth = 12
    \\max_files = 5000
    \\max_bytes = 20000000
    \\changed = false
    \\# changed_base = "origin/main"
    \\
    \\[output]
    \\tree = true
    \\content = false
    \\stats = false
    \\format = "text"
    \\color = "auto"
    \\strict_json = false
    \\compact = false
    \\sort = "name"
    \\tree_sort = "name"
    \\content_preset = "balanced"
    \\content_exclude = []
    \\top_files = 200
    \\
    \\[profiles.review]
    \\tree = true
    \\content = false
    \\stats = true
    \\format = "text"
    \\
    \\[profiles.llm]
    \\tree = true
    \\content = true
    \\stats = true
    \\format = "markdown"
    \\
    \\[profiles.llm-token]
    \\tree = true
    \\content = false
    \\stats = true
    \\format = "markdown"
    \\tree_sort = "lines"
    \\
    \\[profiles.stats]
    \\tree = false
    \\content = false
    \\stats = true
    \\format = "text"
    \\
    ;
}

pub fn writeDefaultToDir(dir: *std.fs.Dir, force: bool) !WriteStatus {
    var file = if (force)
        try dir.createFile(".ztx.toml", .{ .truncate = true })
    else
        dir.createFile(".ztx.toml", .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                std.debug.print(".ztx.toml already exists\n", .{});
                return error.ConfigAlreadyExists;
            },
            else => return err,
        };
    defer file.close();

    try file.writeAll(defaultTemplate());
    return if (force) .overwritten else .created;
}
