const std = @import("std");
const root = @import("root.zig");

const Flag = root.Type.Flag;
const Flags = root.Type.Flags;
const FlagErrs = root.Type.FlagErrs;

pub fn parse_flag(
    arg: []const u8, 
    fmt : root.Type.FlagFmt,
    flags: []Flag,
    comptime defaults: Flags,
    args: *root.Type.ArgIterator,
    cfg: root.Type.ParseConfig
) !void {
    const flag: *Flag = blk: switch (fmt) {
        .Long => break :blk try get_long_flag(flags, arg, cfg),
        .Short => break :blk try get_short_flag(flags, arg[0], cfg),
    };

    const isDefault = try flag.isDefault(defaults);
    if (!isDefault and !cfg.allowDups)
        return root.Type.FlagErrs.DuplicateFlag;

    switch (flag.value) {
        .Argumentative => {
            const next_arg = args.next() orelse {
                return root.Type.FlagErrs.ArgNoArg;
            };

            if (next_arg[0] == '-' or
                !cfg.allowDashAsFirstCharInArgForArg) {
                return root.Type.FlagErrs.ArgNoArg;
            }

            try flag.set_arg(next_arg);
        },

        .Switch => {
            // Only toggle if not already toggled
            if (isDefault) try flag.toggle();
        }
    }
}

pub fn get_long_flag(
    flags: []root.Type.Flag,
    arg: []const u8,
    cfg: root.Type.ParseConfig
) !*root.Type.Flag {
    for (flags) |*flag| {
        if (std.mem.eql(u8, flag.long orelse continue, arg)) return flag;
    }

    if (!cfg.verbose) return root.Type.FlagErrs.NoSuchFlag;

    if (cfg.prefix) |prefix|
        try cfg.writer.?.print("{s}", .{prefix});
    try cfg.writer.?.print("No such flag: --{s}\n", .{arg});

    return root.Type.FlagErrs.NoSuchFlag;
}

pub fn get_short_flag(
    flags: []root.Type.Flag,
    arg: u8,
    cfg: root.Type.ParseConfig
) !*root.Type.Flag {
    for (flags) |*flag| {
        if (arg == flag.short orelse continue) return flag;
    }

    if (!cfg.verbose) return root.Type.FlagErrs.NoSuchFlag;

    if (cfg.prefix) |prefix|
        try cfg.writer.?.print("{s}", .{prefix});
    try cfg.writer.?.print("No such flag: -{c}\n", .{arg});

    return root.Type.FlagErrs.NoSuchFlag;
}
