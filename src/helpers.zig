const std = @import("std");
const root = @import("root.zig");

const Flag = root.Type.Flag;
const Flags = root.Type.Flags;
const ParseError = root.Type.ParseError;

pub fn parse_flag(
    allocator: std.mem.Allocator,
    arg: []const u8,
    fmt : root.Type.FlagFmt,
    flags: []Flag,
    args: *std.process.Args.Iterator,
    cfg: root.Type.ParseConfig
) !void {
    const flag: *Flag = blk: switch (fmt) {
        .Long => break :blk try get_long_flag(flags, arg),
        .Short => break :blk try get_short_flag(flags, arg[0]),
    };

    const isDefault = flag.isDefault();
    {
        // If it's not default and not allow dups, return dup flags error
        // many input flags are allowed to have dups
        const isInputType = flag.value == .Input;
        if (!isDefault and !cfg.allowDups and
            (!isInputType or flag.value.Input != .Many))
                return root.Type.ParseError.DuplicateFlag;
    }

    switch (flag.value) {
        .Input => {
            const next_arg = args.next() orelse {
                return root.Type.ParseError.ArgNoArg;
            };

            if (next_arg[0] == '-' and !cfg.allowDashInput) {
                return root.Type.ParseError.ArgNoArg;
            }

            try flag.setArg(allocator, next_arg);
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
) ParseError!*Flag {
    for (flags) |*flag| {
        if (std.mem.eql(u8, flag.long orelse continue, arg)) return flag;
    } return ParseError.NoSuchFlag;
}

pub fn get_short_flag(
    flags: []root.Type.Flag,
    arg: u8,
) ParseError!*root.Type.Flag {
    for (flags) |*flag| {
        if (arg == flag.short orelse continue) return flag;
    } return ParseError.NoSuchFlag;
}
