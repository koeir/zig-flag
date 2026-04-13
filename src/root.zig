const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

// arg.index is not reset when unsuccessful
pub fn parse(
    args: *std.process.ArgIteratorPosix,
    comptime init_flags: Type.Flags,
    out_flags: []Type.Flag,
    cfg: Type.ParseConfig,
    ) !Type.Flags {

    // Should be compile error really but out_flags must be a runtime var
    if (out_flags.len != init_flags.list.len) {
        @panic("Size of parse result array must match size of init flags array");
    }

    if (cfg.verbose == true and cfg.writer == null) {
        @panic("Verbose is set to true and yet no writer is given");
    }

    // Initialize the output flags for mutation
    for (init_flags.list, 0..) |value, i| {
        out_flags[i] = value;
    }

    if (!args.skip()) return error.NoArgs;
    while (args.next()) |*arg| {
        const fmt: Type.FlagFmt = flagfmt(arg.*) orelse continue;

        switch (fmt) {
            .Short  => helpers.parse_chain(args, out_flags, init_flags, cfg) catch |err| {
                // If its argnoarg and the end of argv hasn't been reached yet,
                // the next arg *must* have been a flag, so -1 for later error checking
                if (err == Type.FlagErrs.ArgNoArg and
                args.index == args.count) args.index -= 1;

                return err;
            },
            .Long   => helpers.parse_long(args, out_flags, init_flags, cfg) catch |err| {
                // See comment directly above
                if (err == Type.FlagErrs.ArgNoArg and
                args.index == args.count) args.index -= 1;

                return err;
            },
        }
    }

    // Reset the iterator when successful
    args.index = 0;

    return Type.Flags {
        .list = out_flags,
    };
}

// Returns whether if a flag is in long or short form
// null if it is not a flag
pub fn flagfmt(arg: []const u8) ?Type.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.FlagFmt.Long;
    return Type.FlagFmt.Short;
}
