const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

// arg.index is not reset when unsuccessful
pub fn parse(
    args: *const std.process.Args,
    argbuf: [][:0]const u8,
    comptime init_flags: Type.Flags,
    out_flags: []Type.Flag,
    errorbuf: ?[]u8,
    cfg: Type.ParseConfig,
    ) !struct { flags: Type.Flags, argv: [][:0]const u8 } {

    var iter = args.iterate();
    var args_iter: Type.ArgIterator = .{
        .args = args,
        .iter = &iter,
        .count = args.vector.len,
    };

    if (args_iter.count > argbuf.len) {
        return error.OutOfMemory;
    }

    // Should be compile error really but out_flags must be a runtime var
    if (out_flags.len != init_flags.list.len) {
        return error.OutOfMemory;
    }

    if (cfg.verbose == true and cfg.writer == null) {
        return error.NoWriter;
    } else {
        defer cfg.writer.?.flush() catch {};
    }

    // Initialize the output flags for mutation
    for (init_flags.list, 0..) |value, i| {
        out_flags[i] = value;
    }

    // Init struct for simpler syntax
    const OutArgs = struct {
        arg: [][:0]const u8,
        index: usize = 0,
    };

    // Use buffer
    var out_args: OutArgs = .{
        .arg = argbuf,
    };

    if (!args_iter.skip()) return error.NoArgs;
    while (args_iter.next()) |*arg| {
        const fmt: Type.FlagFmt = flagfmt(arg.*) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice
            out_args.arg[out_args.index] = arg.*;
            out_args.index += 1;
            continue;
        };

        switch (fmt) {
            .Short  => helpers.parse_chain(&args_iter, out_flags, init_flags, cfg) catch |err| {
                // If its argnoarg and the end of argv hasn't been reached yet,
                // the next arg *must* have been a flag, so -1 so that arg.index
                // is on the erred flag
                if (err == Type.FlagErrs.ArgNoArg and
                args_iter.index != args_iter.count) args_iter.index -= 1;

                if (errorbuf) |e| {
                    const current_arg = args_iter.current().?;

                    if (e.len < current_arg.len) return error.OutOfMemory;
                    @memcpy(e[0..current_arg.len], current_arg);
                }

                return err;
            },
            .Long   => helpers.parse_long(&args_iter, out_flags, init_flags, cfg) catch |err| {
                // See comment directly above
                if (err == Type.FlagErrs.ArgNoArg and
                args_iter.index != args_iter.count) args_iter.index -= 1;

                if (errorbuf) |e| {
                    const current_arg = args_iter.current().?;

                    if (e.len < current_arg.len) return error.OutOfMemory;
                    @memcpy(e[0..current_arg.len], current_arg);
                }

                return err;
            },
        }
    }

    const ret: Type.Flags = .{
        .list = out_flags,
    };

    return .{ .flags = ret, .argv = out_args.arg[0..out_args.index] };
}

// Returns whether if a flag is in long or short form
// null if it is not a flag
pub fn flagfmt(arg: []const u8) ?Type.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.FlagFmt.Long;
    return Type.FlagFmt.Short;
}
