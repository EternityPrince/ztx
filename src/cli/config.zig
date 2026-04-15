const impl = @import("config_impl.zig");

pub const ScanMode = impl.ScanMode;
pub const ColorMode = impl.ColorMode;
pub const OutputFormat = impl.OutputFormat;
pub const SortMode = impl.SortMode;
pub const TreeSortMode = impl.TreeSortMode;
pub const ContentPreset = impl.ContentPreset;
pub const Config = impl.Config;

pub fn initConfigFile(force: bool) !@import("config_file.zig").WriteStatus {
    return impl.initConfigFile(force);
}

pub fn initConfigTemplate() []const u8 {
    return impl.initConfigTemplate();
}
