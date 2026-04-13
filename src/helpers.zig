const std = @import("std");
const root = @import("root.zig");

const Flag = root.Type.Flag;
const Flags = root.Type.Flags;
const FlagErrs = root.Type.FlagErrs;

// Finds and sets the values for flags that have been called in long form
pub fn parse_long(
    args: *std.process.ArgIteratorPosix, 
    flags: []Flag,
    comptime defaults: Flags,
    cfg: root.Type.ParseConfig) !void 
    {

    const flag_arg: [:0]u8 = std.mem.sliceTo(std.os.argv[args.index - 1], 0)[2..:0];
    var flag: *Flag = try get_long_flag(flags, flag_arg, cfg);

    try checkdup(flag, defaults, root.Type.FlagFmt.Long, cfg);

    switch (flag.value) {
        .Switch => |_| {
            // Toggle if not dup
            try flag.toggle();
        },

        .Argumentative => |_| {
            const next_arg = args.next() orelse {
                try cfg.writer.?.print("No argument supplied for --{s}\n", .{ flag.long.? });
                try cfg.writer.?.flush();
                return FlagErrs.ArgNoArg;
            };

            try check_nextarg(flag, next_arg, root.Type.FlagFmt.Long, cfg);

            try flag.set_arg(next_arg);
        },
    }
}

// Same thing but for short flags + chained
pub fn parse_chain(
    args: *std.process.ArgIteratorPosix,
    flags: []Flag,
    comptime defaults: Flags,
    cfg: root.Type.ParseConfig) !void 
    {

    const chain: [:0]u8 = std.mem.sliceTo(std.os.argv[args.index - 1], 0)[1..:0];

    for (chain) |c| {
        var flag: *Flag = try get_short_flag(flags, c, cfg);

        try checkdup(flag, defaults, root.Type.FlagFmt.Short, cfg);

        switch (flag.value) {
            .Switch => |_| {
                try flag.toggle();
            },

            .Argumentative => |_| {
                const next_arg = args.next() orelse {
                    try cfg.writer.?.print("No argument supplied for -{c}\n", .{ flag.short.? });
                    try cfg.writer.?.flush();
                    return FlagErrs.ArgNoArg;
                };

                try check_nextarg(flag, next_arg, root.Type.FlagFmt.Short, cfg);

                try flag.set_arg(next_arg);
        },
        }
    }
}

pub fn check_nextarg(
    flag: *const Flag, 
    arg: []const u8, 
    fmt: root.Type.FlagFmt, 
    cfg: root.Type.ParseConfig) !void 
    {

    if (arg[0] != '-') return;
    if (!cfg.verbose) return FlagErrs.ArgNoArg;

    try cfg.writer.?.print("'{s}' is not a valid argument supplied for: ", .{ arg });
    switch (fmt) {
        .Long => try cfg.writer.?.print("--{s}\n", .{ flag.long.? }),
        .Short => try cfg.writer.?.print("-{c}\n", .{ flag.short.? }),
    }

    try cfg.writer.?.flush();

    return FlagErrs.ArgNoArg;
}

pub fn checkdup(
    flag: *const Flag,
    comptime defaults: Flags,
    fmt: root.Type.FlagFmt,
    cfg: root.Type.ParseConfig) !void 
    {

    if (!try flag.isDefault(defaults)) {
        if (cfg.AllowDups) return;
        if (cfg.verbose) {
            switch (fmt) {
                .Long => try cfg.writer.?.print("{}: --{s}\n",
                    .{ FlagErrs.DuplicateFlag, flag.long.? }),
                .Short => try cfg.writer.?.print("{}: -{c}\n", .{ 
                    FlagErrs.DuplicateFlag, flag.short.? }),
            }
        }

        try cfg.writer.?.flush();
        return FlagErrs.DuplicateFlag;
    }
}

pub fn get_long_flag(flags: []root.Type.Flag, arg: []const u8, cfg: root.Type.ParseConfig) !*root.Type.Flag {
    for (flags) |*flag| {
        if (std.mem.eql(u8, flag.long orelse continue, arg)) return flag;
    }

    if (cfg.verbose) try cfg.writer.?.print("No such flag: --{s}\n", .{ arg });
    return root.Type.FlagErrs.NoSuchFlag;
}

pub fn get_short_flag(flags: []root.Type.Flag, arg: u8, cfg: root.Type.ParseConfig) !*root.Type.Flag {
    for (flags) |*flag| {
        if (arg == flag.short orelse continue) return flag;
    }

    if (cfg.verbose) try cfg.writer.?.print("No such flag: -{c}\n", .{ arg });
    return root.Type.FlagErrs.NoSuchFlag;
}
