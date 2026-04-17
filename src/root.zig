const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

// arg.index is not reset when unsuccessful
pub fn parse(
    allocator: *std.mem.Allocator,
    args: *const std.process.Args,
    comptime init_flags: Type.Flags,
    errorbuf: ?[]u8,
    cfg: Type.ParseConfig,
) !struct { flags: Type.Flags, argv: *[]*[:0]const u8 } {
    if (cfg.verbose == true and cfg.writer == null) return error.NoWriter;
    defer cfg.writer.?.flush() catch {};

    var iter = args.iterate();
    var args_iter: Type.ArgIterator = .{
        .args = args,
        .iter = &iter,
        .count = args.vector.len,
    };

    // Initialize the parsed flags
    var out_flags = try allocator.alloc(Type.Flag, init_flags.list.len);
    for (init_flags.list, 0..) |value, i| out_flags[i] = value;

    // argbuf for args array without flags
    var argbuf = try allocator.alloc(*[:0]u8, args.vector.len);

    // Init struct for simpler syntax
    const OutArgs = struct {
        arg: []*[:0]const u8,
        index: usize = 0,

        pub fn add_arg(self: *@This(), arg: *[:0]const u8) void {
            self.arg[self.index] = arg;
            self.index += 1;
        }
    };

    // Use buffer
    var out_args: OutArgs = .{
        .arg = &argbuf,
    };

    if (!args_iter.skip()) return error.NoArgs;
    while (args_iter.next()) |*arg| {
        const fmt: Type.FlagFmt = flagfmt(arg.*) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice

            out_args.add_arg(arg);
            continue;
        };

        switch (fmt) {
            .Short => helpers.parse_chain(&args_iter, out_flags, init_flags, cfg) catch |err| {
                try helpers.put_error(&errorbuf, err, &args_iter);
                return err;
            },
            .Long => helpers.parse_long(&args_iter, out_flags, init_flags, cfg) catch |err| {
                try helpers.put_error(&errorbuf, err, &args_iter);
                return err;
            },
        }
    }

    const ret: Type.Flags = .{
        .list = out_flags,
    };

    return .{ .flags = ret, .argv = &out_args.arg };
}

// Returns whether if a flag is in long or short form
// null if it is not a flag
pub fn flagfmt(arg: []const u8) ?Type.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.FlagFmt.Long;
    return Type.FlagFmt.Short;
}
