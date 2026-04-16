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

    // Make mutable flagparse array "buffer" in stack
    var flagarr: [initflags.list.len]flagparse.Type.Flag = undefined;
    
    // Make buffer for argv list omitting flags AND arguments for flags
    // can be any size; parse fails if args.count > argbuf.len
    //
    // upon parsing, this points to init.min.args
    var argbuf: [20][:0]const u8 = undefined;

    // Stores the flag that erred, 256 is pretty overkill as it is only populated
    // with a flag's .long/.short
    var errorbuf: [256]u8 = undefined;

    // actual parse, returns a tuple of Flags and resulting args
    const result = flagparse.parse(&min.args, argbuf[0..], initflags, &flagarr, &errorbuf,
    .{ .allowDups = false, .verbose = true, .writer = stderr, .prefix = "my-program: " }) catch |err| {
        if (err != flagparse.Type.FlagErrs.ArgNoArg) return;

        const arg: []const u8 = &errorbuf;
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

        try stdout.writeAll("\n");
        return;
    };

    const flags = result.flags;
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
    try stdout.print("The path is {s}!\n", .{ try flags.get_value("file", flagparse.Type.Argumentative) });
    try stdout.print("Recursion is {any}\n", .{ try flags.get_value("recursive", flagparse.Type.Switch) });

    // Also works with the Flags struct
    try stdout.writeAll("\n");
    try stdout.writeAll("Options:\n");
    try stdout.print("{f}", .{ initflags });

    try stdout.writeAll("\n");
    try stdout.writeAll("Flagless argv list:\n");
    for (flagless_args) |argv| {
        try stdout.print("{s}\n", .{ argv });
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
        //
        // They will however, NOT accept any arg that starts with "-"
        // e.g. -p -r noob
        // will yield an error
        .{
            .name = "file",
            .long = "path",
            .short = 'p',
            // Argumentative flags should not be initialized as undefined,
            // instead, make a reference to array of 1024 u8s
            .value = .{ .Argumentative = .{0} ** 1024 },
            .desc = "Path to file",
        },

        .{
            .name = "hi",
            .short = 'h',
            .desc = "hello",
            .value = .{ .Switch = false }
        },
        .{
            .name = "hello",
            .long = "hello",
            .desc = "hi",
            .value = .{  .Argumentative = .{0} ** 1024 }
        },
    },
    
};
