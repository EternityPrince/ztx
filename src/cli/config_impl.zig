const core = @import("config_core.zig");
const config_file = @import("config_file.zig");

pub const ScanMode = core.ScanMode;
pub const ColorMode = core.ColorMode;
pub const OutputFormat = core.OutputFormat;
pub const SortMode = core.SortMode;
pub const TreeSortMode = core.TreeSortMode;
pub const ContentPreset = core.ContentPreset;
pub const Config = core.Config;

pub fn initConfigFile(force: bool) !config_file.WriteStatus {
    return core.initConfigFile(force);
}

pub fn initConfigTemplate() []const u8 {
    return core.initConfigTemplate();
}

test {
    _ = @import("config_impl_test.zig");
}
