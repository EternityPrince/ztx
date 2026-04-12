const std = @import("std");

pub const ScanMode = enum {
    default,
    full,
};

pub const ColorMode = enum {
    auto,
    always,
    never,
};

pub const OutputFormat = enum {
    text,
    markdown,
    json,
};

pub fn parseScanMode(value: []const u8) !ScanMode {
    if (std.mem.eql(u8, value, "default")) return .default;
    if (std.mem.eql(u8, value, "full")) return .full;
    return error.InvalidScanMode;
}

pub fn parseColorMode(value: []const u8) !ColorMode {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "always")) return .always;
    if (std.mem.eql(u8, value, "never")) return .never;
    return error.InvalidColorMode;
}

pub fn parseOutputFormat(value: []const u8) !OutputFormat {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "markdown")) return .markdown;
    if (std.mem.eql(u8, value, "json")) return .json;
    return error.InvalidOutputFormat;
}

pub fn colorModeLabel(mode: ColorMode) []const u8 {
    return switch (mode) {
        .auto => "auto",
        .always => "always",
        .never => "never",
    };
}

pub fn scanModeLabel(mode: ScanMode) []const u8 {
    return switch (mode) {
        .default => "default",
        .full => "full",
    };
}

pub fn outputFormatLabel(format: OutputFormat) []const u8 {
    return switch (format) {
        .text => "text",
        .markdown => "markdown",
        .json => "json",
    };
}
