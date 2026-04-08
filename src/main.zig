const std = @import("std");
const flag = @import("flagparse");

pub fn main() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var args: std.process.ArgIteratorPosix = .init();

    var flagarr: [initflags.list.len]flag.Flag = undefined;
    const flags = try flag.parse(&args, initflags, &flagarr, .{ .verbose = true });

    try stdout.writeAll("Toggled flags:\n");
    // Formatted print for each flag
    for (flags.list) |f| {
        if (!try f.isDefault(initflags)) try stdout.print("{f}\n", .{ f } );
    }

    // Also works with the Flags struct
    try stdout.writeAll("\n");
    try stdout.writeAll("Options:\n");
    try stdout.print("{f}", .{ initflags });
}

// Initialize flags and their default values
// name doesn't really matter as long as the 
// members are all of type Flag
const initflags: flag.Flags = .{
    .list = &[_] flag.Flag 
    {
            flag.Flag {
                .name = "recursive",
                .long = "recursive",
                .short = 'r',
                .value = .{ .Switch = false },
                .desc = "Recurse into directories",
            },

            flag.Flag {
                .name = "force",
                .long = "force",
                .short = 'f',
                .value = .{ .Switch = false },
                .desc = "Skip confirmation prompts",
            },

            flag.Flag {
                .name = "file",
                .long = "path",
                .short = 'p',
                // Should not be undef
                .value = .{ .Argumentative = "" },
                .desc = "Path to file",
            }
    },
};
