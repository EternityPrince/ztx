const std = @import("std");
const cli = @import("../cli/config.zig");

const ignored_names = [_][]const u8{
    ".git",
    ".zig-cache",
    "zig-out",
    ".DS_Store",
};

const ignored_file_extansions = [_][]const u8{
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".pdf",
    ".zip",
    ".tar",
    ".gz",
    ".exe",
};

const default_source_extensions = [_][]const u8{
    ".zig",
    ".c",
    ".h",
    ".cpp",
    ".hpp",
    ".cc",
    ".hh",
    ".go",
    ".rs",
    ".py",
    ".js",
    ".ts",
    ".java",
    ".kt",
    ".swift",
    ".php",
    ".rb",
    ".lua",
    ".cs",
    ".sh",
    ".bash",
    ".zsh",
    ".sql",
    ".html",
    ".css",
    ".scss",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".xml",
    ".md",
    ".txt",
};

pub fn shouldScanFile(name: []const u8, config: cli.Config) bool {
    switch (config.scan_mode) {
        .default => return matchesDefaultSources(name),
        .full => return true,
    }
}

pub fn shouldSkip(name: []const u8, kind: std.fs.Dir.Entry.Kind) bool {
    if (matchesIgnoredName(name)) return true;
    if (matchesIgnoredExtansion(name) and kind == .file) return true;
    return false;
}

fn matchesDefaultSources(name: []const u8) bool {
    const extension = std.fs.path.extension(name);

    inline for (default_source_extensions) |ext| {
        if (std.mem.eql(u8, ext, extension)) return true;
    }
    return false;
}

fn matchesIgnoredName(name: []const u8) bool {
    inline for (ignored_names) |ignored| {
        if (std.mem.eql(u8, name, ignored)) return true;
    }
    return false;
}

fn matchesIgnoredExtansion(name: []const u8) bool {
    const file_extansion = std.fs.path.extension(name);

    inline for (ignored_file_extansions) |ignored| {
        if (std.mem.eql(u8, file_extansion, ignored)) return true;
    }
    return false;
}
