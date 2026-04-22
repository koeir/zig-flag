const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

// Memory returned must be freed
pub fn parse(
    allocator: std.mem.Allocator,
    args: std.process.Args,
    comptime defaults: Type.Flags,
    errptr: *?[]const u8,
    cfg: Type.ParseConfig,
) !Type.ParseResult {
    if (cfg.verbose == true and cfg.writer == null) return error.NoWriter;
    defer if (cfg.verbose) cfg.writer.?.flush()catch{};

    var iter = args.iterate();
    var args_iter: Type.ArgIterator = .{
        .args = args,
        .iter = &iter,
        .count = args.vector.len,
    };

    // Initialize the parsed flags
    var out_flags = try allocator.alloc(Type.Flag, defaults.list.len);
    errdefer allocator.free(out_flags);
    for (defaults.list, 0..) |value, i| out_flags[i] = value;

    // Use buffer
    var out_args = Type.OutArgs{};
    errdefer if (out_args.args) |value| allocator.free(value);

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
            .Long   => {
                helpers.parse_flag(
                    arg[2..], fmt, 
                    out_flags, defaults, 
                    &args_iter, cfg) catch |err| {
                    if (!cfg.verbose) return err;

                    if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
                    try cfg.writer.?.print("{s}: {s}\n", .{ arg, error_message(err) orelse @errorName(err) });

                    errptr.* = arg[2..];
                    return err;
                };
            },
            .Short  => {
                for (arg[1..], 1..) |c, i| {
                    helpers.parse_flag(
                        &[_]u8 {c}, fmt, 
                        out_flags, defaults, 
                        &args_iter, cfg
                    ) catch |err| {
                        if (!cfg.verbose) return err;

                        if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
                        try cfg.writer.?.print("-{c}: {s}\n", .{ c, error_message(err) orelse @errorName(err) });

                        errptr.* = arg[i..i+1];
                        return err;
                    };
                }
            },
        }
    }

    if (args_iter.index == 1 and cfg.errOnNoArgs) return error.NoArgs;

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

// returns error messages for flag errors
// does not include errors that should not
// appear in production
pub fn error_message(err: Type.FlagErrs) ?[]const u8 {
    return switch (err) {
        error.NoArgs         => "Missing arguments",
        error.NoSuchFlag     => "No such flag",
        error.DuplicateFlag  => "Duplicate flag",
        error.ArgNoArg       => "No argument supplied",
        else            => null,
    };
}
