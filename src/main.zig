const std = @import("std");
const flag = @import("flagparse");

pub fn main() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var args: std.process.ArgIteratorPosix = .init();
    try flag.parse(&args, stdout);
}
