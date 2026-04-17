const std = @import("std");
const flagparse = @import("flagparse");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const min = init.minimal;

    var stderr_writer: std.Io.File.Writer = .init( .stderr(), io, &.{});
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    var stdout_writer: std.Io.File.Writer = .init( .stdout(), io, &.{});
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var gpa = std.heap.DebugAllocator(.{}){};
    var fba: std.heap.ArenaAllocator = .init(gpa.allocator());
    defer fba.deinit();

    // points to last arg on error
    // not necessarily the arg that caused the error
    var errptr: [*:0]const u8 = undefined;

    // actual parse, returns a tuple of Flags and resulting args
    const result = flagparse.parse(&fba.allocator(), &min.args, initflags, &errptr,
    .{ .allowDups = false, .verbose = true, .writer = stderr, .prefix = "my-program: " }) catch |err| {
        if (err != flagparse.Type.FlagErrs.ArgNoArg) return;

        const arg: []const u8 = std.mem.span(errptr);
        const fmt = flagparse.flagfmt(arg) orelse return;
        var flagtmp: *const flagparse.Type.Flag = undefined;

        // "Usage" output when parse fails
        try stdout.writeAll("Usage:\n");
        switch (fmt) {
            .Long   => {
                flagtmp = initflags.get_with_flag(arg[2..]).?;
                try stdout.print("{f}\n", .{ flagtmp.* });
            },
            .Short  => {
                for (arg[1..]) |c| {
                    flagtmp = initflags.get_with_flag(&[_]u8 {c}) orelse continue;
                    try stdout.print("{f}\n", .{ flagtmp.* });
                }
            }
        }

        return;
    };

    // retrieve tuple values
    const flags: flagparse.Type.Flags = result.flags;
    const flagless_args = result.argv;

    try stdout.writeAll("Toggled flags:\n");
    // Formatted print for each flagparse
    for (flags.list) |f| {
        if (!try f.isDefault(initflags)) try stdout.print("{f}\n", .{ f } );
    }

    try stdout.writeAll("\n");
    try stdout.writeAll("Values:\n");
    for (flags.list) |f| {
        if (try f.isDefault(initflags)) continue;

        try stdout.print("{s}: {f}\n", .{ f.name, f.value });
    }

    try stdout.writeAll("\n");
    const file = try flags.get_value("file", flagparse.Type.Argumentative);
    if (file) |val| {
        try stdout.print("The path is {s}!\n", .{ val });
    }
    try stdout.print("Recursion is {any}\n", .{ try flags.get_value("recursive", flagparse.Type.Switch) });

    // Also works with the Flags struct
    try stdout.writeAll("\n");
    try stdout.writeAll("Options:\n");
    try stdout.print("{f}", .{ initflags });

    try stdout.writeAll("\n");
    try stdout.writeAll("Flagless argv list:\n");

    if (flagless_args) |args| {
        for (args) |value| {
            try stdout.print("{s}\n", .{ value });
        }
    }
}

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type flagparse
const initflags: flagparse.Type.Flags = .{
    .list = &[_] flagparse.Type.Flag
    {
        .{
            .name = "recursive",
            .long = "recursive",
            .short = 'r',
            .value = .{ .Switch = false },
            .desc = "Recurse into directories",
        },

        .{
            .name = "force",
            .long = "force",
            .short = 'f',
            .value = .{ .Switch = false },
            .desc = "Skip confirmation prompts",
        },

        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "file",
            .long = "path",
            .short = 'p',
            .value = .{ .Argumentative = null },
            .desc = "Path to file",
        },
    }
};
