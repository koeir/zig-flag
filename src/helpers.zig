const std = @import("std");
const root = @import("root.zig");

const Flag = root.Type.Flag;
const Flags = root.Type.Flags;
const FlagError = root.Type.FlagError;

pub fn parse_flag(
    arg: []const u8, 
    fmt : root.Type.FlagFmt,
    flags: []Flag,
    args: *root.Type.ArgIterator,
    cfg: root.Type.ParseConfig
) FlagError!void {
    const flag: *Flag = blk: switch (fmt) {
        .Long => break :blk try get_long_flag(flags, arg),
        .Short => break :blk try get_short_flag(flags, arg[0]),
    };

    const isDefault = flag.isDefault();
    if (!isDefault and !cfg.allowDups)
        return root.Type.FlagError.DuplicateFlag;

    switch (flag.value) {
        .Input => {
            const next_arg = args.next() orelse {
                return root.Type.FlagError.ArgNoArg;
            };

            if (next_arg[0] == '-' and
                !cfg.allowDashInput) {
                return root.Type.FlagError.ArgNoArg;
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
) FlagError!*Flag {
    for (flags) |*flag| {
        if (std.mem.eql(u8, flag.long orelse continue, arg)) return flag;
    } return FlagError.NoSuchFlag;
}

pub fn get_short_flag(
    flags: []root.Type.Flag,
    arg: u8,
) FlagError!*root.Type.Flag {
    for (flags) |*flag| {
        if (arg == flag.short orelse continue) return flag;
    } return FlagError.NoSuchFlag;
}
