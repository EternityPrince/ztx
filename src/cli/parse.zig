const impl = @import("parse_impl.zig");
const std = @import("std");

pub const RunOptions = impl.RunOptions;
pub const InitOptions = impl.InitOptions;
pub const Command = impl.Command;
pub const ParsedArgs = impl.ParsedArgs;

pub fn parseArgs(allocator: std.mem.Allocator) !ParsedArgs {
    return impl.parseArgs(allocator);
}

pub fn printHelp() !void {
    return impl.printHelp();
}
