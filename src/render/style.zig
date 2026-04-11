pub const ansi = struct {
    pub const reset = "\x1b[0m";
    pub const section = "\x1b[1;36m";
    pub const label = "\x1b[90m";
    pub const value = "\x1b[1;33m";
    pub const ext = "\x1b[92m";
    pub const tree = "\x1b[90m";
    pub const dir = "\x1b[1;34m";
    pub const file = "\x1b[37m";
    pub const path = "\x1b[95m";
    pub const separator = "\x1b[90m";
    pub const line_number = "\x1b[90m";
};

pub const Style = struct {
    use_color: bool,

    pub fn start(self: Style, writer: anytype, color_code: []const u8) !void {
        if (!self.use_color) return;
        try writer.writeAll(color_code);
    }

    pub fn reset(self: Style, writer: anytype) !void {
        if (!self.use_color) return;
        try writer.writeAll(ansi.reset);
    }

    pub fn write(self: Style, writer: anytype, color_code: []const u8, text: []const u8) !void {
        try self.start(writer, color_code);
        try writer.writeAll(text);
        try self.reset(writer);
    }

    pub fn print(self: Style, writer: anytype, color_code: []const u8, comptime fmt: []const u8, args: anytype) !void {
        try self.start(writer, color_code);
        try writer.print(fmt, args);
        try self.reset(writer);
    }
};

test "style writes ANSI codes when enabled" {
    var buffer: [256]u8 = undefined;
    var fbs = @import("std").io.fixedBufferStream(&buffer);
    const style = Style{ .use_color = true };

    try style.write(fbs.writer(), ansi.value, "42");
    const output = fbs.getWritten();
    try @import("std").testing.expect(@import("std").mem.indexOf(u8, output, "\x1b[") != null);
}

test "style omits ANSI codes when disabled" {
    var buffer: [256]u8 = undefined;
    var fbs = @import("std").io.fixedBufferStream(&buffer);
    const style = Style{ .use_color = false };

    try style.write(fbs.writer(), ansi.value, "42");
    try @import("std").testing.expectEqualStrings("42", fbs.getWritten());
}
