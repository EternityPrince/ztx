//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn bufferedPrint() !void {}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
