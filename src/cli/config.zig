const parse = @import("parse.zig");

pub const Config = struct {
    show_content: bool,
    show_tree: bool,
    show_help: bool,
    show_stats: bool,

    const Self = @This();

    pub fn fromOptions(options: parse.Options) !Self {
        var config = Self{
            .show_content = options.show_content,
            .show_tree = options.show_tree,
            .show_help = options.show_help,
            .show_stats = options.show_stats,
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
};

