const std = @import("std");
const policy = @import("../policy/walker_ignore.zig");
const cli = @import("../cli/config.zig");

pub fn shouldExcludeContentByPolicy(config: *const cli.Config, file_name: []const u8, rel_path: []const u8) bool {
    if (config.content_preset == .balanced) {
        inline for (balanced_content_exclude_patterns) |pattern| {
            if (patternMatchesPathOrBasename(pattern, file_name, rel_path)) return true;
        }
    }

    for (config.content_exclude_patterns.items) |pattern| {
        if (patternMatchesPathOrBasename(pattern, file_name, rel_path)) return true;
    }

    return false;
}

fn patternMatchesPathOrBasename(pattern: []const u8, file_name: []const u8, rel_path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, pattern, '/') != null) {
        return policy.matchesPathPattern(pattern, rel_path);
    }
    return policy.matchesPathPattern(pattern, file_name);
}

const balanced_content_exclude_patterns = [_][]const u8{
    "README*",
    "CHANGELOG*",
    "CHANGES*",
    "LICENSE*",
    "COPYING*",
    "RELEASING*",
    ".env",
    ".env.*",
    ".editorconfig",
    ".clang*",
    ".prettierrc*",
    ".eslintrc*",
    ".npmrc",
    ".yarnrc*",
    ".tool-versions",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "Cargo.lock",
    "Gemfile.lock",
    "go.sum",
    ".github/workflows/*",
    "packaging/**",
};
