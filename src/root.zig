const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

// Memory returned must be freed
pub fn parse(
    allocator: *const std.mem.Allocator,
    args: *const std.process.Args,
    comptime init_flags: Type.Flags,
    errptr: *[*:0]const u8,
    cfg: Type.ParseConfig,
) !struct { flags: Type.Flags, argv: ?[][:0]const u8 } {
    if (cfg.verbose == true and cfg.writer == null) return error.NoWriter;
    defer if (cfg.verbose) cfg.writer.?.flush()catch{};

    var iter = args.iterate();
    var args_iter: Type.ArgIterator = .{
        .args = args,
        .iter = &iter,
        .count = args.vector.len,
    };

    // Initialize the parsed flags
    var out_flags = try allocator.alloc(Type.Flag, init_flags.list.len);
    errdefer allocator.free(out_flags);
    for (init_flags.list, 0..) |value, i| out_flags[i] = value;

    // Use buffer
    var out_args = Type.OutArgs{};
    errdefer if (out_args.args) |value| allocator.free(value);

    // put current arg in iteration in errptr on error
    errdefer errptr.* = blk: {
        if (args_iter.index > 0) {
            break :blk args.vector[args_iter.index-1];
        } else break :blk args.vector[0];
    };

    if (!args_iter.skip()) return error.NoArgs;
    while (args_iter.next()) |arg| {
        const fmt: Type.FlagFmt = flagfmt(arg) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice

            try out_args.add_arg(allocator, arg, args);
            continue;
        };

        switch (fmt) {
            .Short => try helpers.parse_chain(&args_iter, out_flags, init_flags, cfg),
            .Long => try helpers.parse_long(&args_iter, out_flags, init_flags, cfg)
        }
    }

    if (args_iter.index == 1) return error.NoArgs;

    // shrink out_args because it's guaranteed to be <= args
    try out_args.resize(allocator);

    const ret: Type.Flags = .{
        .list = out_flags,
    };

    return .{ .flags = ret, .argv = out_args.args };
}

// Returns whether if a flag is in long or short form
// null if it is not a flag
pub fn flagfmt(arg: []const u8) ?Type.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.FlagFmt.Long;
    return Type.FlagFmt.Short;
}
