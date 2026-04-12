const std = @import("std");
const parse = @import("parse.zig");

pub const ScanMode = enum {
    default,
    full,
};

pub const Config = struct {
    show_content: bool,
    show_tree: bool,
    show_help: bool,
    show_stats: bool,
    use_color: bool,
    scan_mode: ScanMode,

    const Self = @This();

    pub fn fromOptions(options: parse.Options) !Self {
        var config = Self{
            .show_content = options.show_content,
            .show_tree = options.show_tree,
            .show_help = options.show_help,
            .show_stats = options.show_stats,
            .use_color = detectColorMode(options.no_color),
            .scan_mode = options.scan_mode,
        };

        config.normalize();
        try config.validate();

        return config;
    }

    fn normalize(self: *Self) void {
        if (self.show_help) {
            self.show_content = false;
            self.show_tree = false;
            self.show_stats = false;
        }
    }

    pub fn validate(self: Self) !void {
        if (self.isEmpty()) {
            return error.EmptyOutput;
        }
    }

    pub fn isEmpty(self: Self) bool {
        return !self.show_content and
            !self.show_tree and
            !self.show_stats and
            !self.show_help;
    }

    fn detectColorMode(no_color: bool) bool {
        if (no_color) return false;
        return std.fs.File.stdout().isTty();
    }
};

test "fromOptions applies help normalization and no-color override" {
    const options = parse.Options{
        .show_tree = true,
        .show_content = true,
        .show_stats = true,
        .no_color = true,
        .show_help = true,
        .scan_mode = .default,
    };

    const config = try Config.fromOptions(options);

    try std.testing.expect(config.show_help);
    try std.testing.expect(!config.show_tree);
    try std.testing.expect(!config.show_content);
    try std.testing.expect(!config.show_stats);
    try std.testing.expect(!config.use_color);
}

test "validate fails for fully disabled output" {
    const config = Config{
        .show_content = false,
        .show_tree = false,
        .show_help = false,
        .show_stats = false,
        .use_color = false,
        .scan_mode = .default,
    };

    try std.testing.expectError(error.EmptyOutput, config.validate());
}
