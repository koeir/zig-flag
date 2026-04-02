const std = @import("std");

const FlagFmt = enum {
    Long, Short,
};

pub fn parse(args: *std.process.ArgIteratorPosix, stdout: *std.Io.Writer) !void {
    while (args.next()) |arg| {
        const fmt: FlagFmt = flagfmt(arg) orelse continue;
        switch (fmt) {
            .Long   => try stdout.print("{s}: {s}\n", .{ arg[2..], @tagName(fmt)}),
            .Short  => try stdout.print("{s}: {s}\n", .{ arg[1..], @tagName(fmt)}),
        }
    }
}

fn flagfmt(arg: []const u8) ?FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return FlagFmt.Long;
    return FlagFmt.Short;
}
