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
    defer if (gpa.deinit() == std.heap.Check.leak) @panic("MEMORY LEAK");

    // points to erred flag
    var errptr: ?[]const u8 = null;

    // actual parse, returns a tuple of Flags and resulting args
    const result = flagparse.parse(gpa.allocator(), min.args, initflags, &errptr,
    .{ .allowDups = false, .verbose = true, .writer = stderr, .prefix = "my-program: ", .errOnNoArgs = true, }, ) catch |err| {
        if (err != flagparse.Type.FlagError.ArgNoArg) return;

        const arg: []const u8 = errptr orelse return;
        const flagtmp = initflags.getWithFlag(arg) orelse return;

        // "Usage" output when parse fails
        try stdout.writeAll("\nUsage:\n");
        try stdout.print("{f}\n", .{ flagtmp.* });

        return;
    }; defer result.deinit(gpa.allocator());

    // retrieve tuple values
    const flags: flagparse.Type.Flags = result.flags;
    const flagless_args = result.argv;

    // change padding
    // warning:
    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    //
    // so make sure the padding is enough
    flagparse.Type.Flag.fmt = .{
        .padding = .{
            .left = 5,
            .center = 30,
        },
        .greyOutFiller = true,
        .fillerStyle = '.',
    };

    try stdout.writeAll("Toggled flags:\n");
    // Formatted print for each flagparse
    for (flags.list) |f| {
        if (!f.isDefault()) try stdout.print("{f}\n", .{ f } );
    }

    try stdout.writeAll("\n");
    const file: ?[:0]const u8 = flags.getValue("file").?.Input;
    if (file) |val| {
        try stdout.print("The path is {s}!\n", .{ val });
    } try stdout.writeAll("\n");

    try stdout.writeAll("Flagless argv list:\n");
    if (flagless_args) |args| {
        for (args) |value| {
            try stdout.print("{s}\n", .{ value });
        }
    }

    // Also works with the Flags struct
    try stdout.writeAll("\nUsage:\n");
    try initflags.usage(stdout, .{ .padding_left = 2 });

    // Different fillerStyle
    flagparse.Type.Flag.fmt = .{
        .columns = .one,
        .padding = .{
            .left = 5,
        },
        .fillerStyle = ' ',  // default
        .greyOutDesc = true,
    };
    try stdout.writeAll("\nUsage:\n\n");
    try initflags.usage(stdout, .{ .padding_left = 2, .tagStyle = .underline });
}

const Switch = flagparse.Type.Switch;
const Input = flagparse.Type.Input;

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type flagparse
const initflags: flagparse.Type.Flags = .{
    .list = &[_] flagparse.Type.Flag
    {
        .{
            .name = "recursive",
            .tag = "Switches",
            .long = "recursive",
            .short = 'r',
            .value = Switch,
            .desc = "Recurse into directories",
        },
        .{
            .name = "force",
            .tag = "Switches",
            .long = "force",
            .short = 'f',
            .vanity = "-[n|f], --[no-]force",
            .value = Switch,
            .desc = "Skip confirmation prompts",
        },
        .{  // by default, untagged flags will not be printed
            .name = "no-force",
            .long = "no-force",
            .short = 'n',
            .value = Switch,
            .desc = "Do not skip confirmation prompts",
        },
        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "file",
            .tag = "Input",
            .long = "path",
            .short = 'p',
            .value = Input,
            .desc = "Path to file",
        },
    }
};
