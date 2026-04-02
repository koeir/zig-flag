const std = @import("std");

const FlagFmt = enum {
    Long, Short,
};

pub fn parse(args: *std.process.ArgIteratorPosix, stdout: *std.Io.Writer, flags: anytype) !void {
    inFlags(flags);

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

fn inFlags(flags: anytype) void {
    inline for (@typeInfo(flags).@"struct".decls) |decls| {
        std.debug.print("{s}\n", .{ decls.name });
    }
} 
