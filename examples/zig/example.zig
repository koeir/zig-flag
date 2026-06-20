const std = @import("std");
const zigflag = @import("src/root.zig");

const defaults = @import("./flags_init.zig").defaults;
const Flags = zigflag.Parse.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const min = init.minimal;

    var stderr_writer: std.Io.File.Writer = .init( .stderr(), io, &.{});
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    const parsecfg: zigflag.Parse.ParseConfig = .{
        .allowDashInput = true,
        .exitFirstErr = false,
        .allowDups = true,
        .delimiters = ",:",
        .errOnNoArgs = false,
    };
    
    const parse = try zigflag.parse(init.gpa, min.args, defaults, parsecfg);
    defer parse.deinit(init.gpa);

    const result = switch (parse) {
        .Ok  => | ok | ok,
        .Err => |errs| {
            for (errs.items) |err| {
                if (err.cause) |cause| {
                    std.debug.print("{s}: ", .{ cause });
                } std.debug.print("{s}\n", .{ @errorName(err.err) });
            } return;
        },
    };

    const flags: Flags = result.flags;
    const argv: []const [:0]const u8 = result.argv;

    zigflag.Type.Flag.fmt = .{
        .columns = .one,
        .greyOutDesc = true,
    };

    try defaults.usage(stderr, .{ .tagStyle = .underline });

    std.debug.print("\nINDIVIDUAL PRINTING:\n", .{});
    for (defaults.list) |flag| {
        std.debug.print("{f}\n", .{flag});
    }

    if (flags.recursive) {
        std.debug.print("\nRECURSIVE:\n", .{});
        const recursive = comptime defaults.compFind("recursive");
        std.debug.print("{f}\n", .{recursive});
    }

    if (flags.force) {
        std.debug.print("\nFORCE:\n", .{});
        const force = result.inner.flags.getWithFlag("force", .Long).?;
        std.debug.print("{f}\n", .{force});
    }

    std.debug.print("\n", .{});
    if (flags.files) |files| {
        std.debug.print("files:\n", .{});
        for (files) |file| {
            std.debug.print("{s} ", .{file});
        } std.debug.print("\n", .{});
    }

    const path = flags.path orelse "nowhere";
    std.debug.print("{s}\n", .{ path });

    std.debug.print("\n", .{});
    std.debug.print("flagless args:\n", .{});
    for (argv) |arg| {
        std.debug.print("{s} ", .{arg});
    } std.debug.print("\n", .{});
}
