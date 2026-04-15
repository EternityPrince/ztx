const std = @import("std");
const core = @import("parse_core.zig");

pub const RunOptions = core.RunOptions;
pub const InitOptions = core.InitOptions;
pub const Command = core.Command;
pub const ParsedArgs = core.ParsedArgs;

pub fn parseArgs(allocator: std.mem.Allocator) !ParsedArgs {
    return core.parseArgs(allocator);
}

pub fn parseArgsFrom(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    return core.parseArgsFrom(allocator, args);
}

pub fn printHelp() !void {
    return core.printHelp();
}

test {
    _ = @import("parse_impl_test.zig");
}
