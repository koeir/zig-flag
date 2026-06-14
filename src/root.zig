const std = @import("std");
const helpers = @import("helpers.zig");

pub const Type = @import("Type.zig");
pub const flagfmt = helpers.flagfmt;

// Memory returned must be freed
pub fn parse(
    allocator: std.mem.Allocator,
    args: std.process.Args,
    comptime defaults: Type.Flags,
    errptr: *?[]const u8,
    cfg: ParseConfig,
) !Type.ParsedResult(defaults) {
    if (cfg.verbose == true and cfg.writer == null) return error.NoWriter;

    var iter = args.iterate();

    // Initialize the parsed flags
    var out_flags = try allocator.alloc(Type.Flag, defaults.list.len);
    errdefer allocator.free(out_flags);
    for (defaults.list, 0..) |*value, i| {
        out_flags[i] = value.*;
        out_flags[i].default = value;
    }

    var out_args: *std.ArrayList([:0]const u8) = try allocator.create(std.ArrayList([:0]const u8));
    out_args.* = try std.ArrayList([:0]const u8).initCapacity(allocator, args.vector.len);
    errdefer out_args.deinit(allocator);
    errdefer allocator.destroy(out_args);

    var isErred = false;
    var out_error: anyerror = undefined;
    while (iter.next()) |arg| {
        const fmt: Type.FlagFmt = helpers.flagfmt(arg) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice
            try out_args.append(allocator, arg);
            continue;
        };

        switch (fmt) {
            .Long   => {
                errdefer errptr.* = arg;

                helpers.parse_flag(
                    allocator,
                    arg[2..], fmt,
                    out_flags, &iter,
                    cfg
                ) catch |err| {
                    isErred = true;

                    if (cfg.verbose) {
                        if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
                        try cfg.writer.?.print("{s}: {s}\n", .{ arg,
                            error_message(err) orelse @errorName(err) });
                    }

                    out_error = err;
                    if (cfg.exitFirstErr) return err;
                };
            },
            .Short  => {
                for (arg[1..]) |c| {

                    helpers.parse_flag(
                        allocator, &[_]u8 {c}, fmt, out_flags, &iter, cfg
                    ) catch |err| {
                        isErred = true;
                        if (cfg.verbose){
                            if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
                            try cfg.writer.?.print("-{c}: {s}\n", .{
                                c, error_message(err) orelse @errorName(err) });
                        }

                        errptr.* = try std.mem.concat(allocator, u8, &.{
                            errptr.* orelse "-", &[_]u8{c}
                        });

                        out_error = err;
                        if (cfg.exitFirstErr) return err;
                    };
                }
            },
        }
    }

    if (isErred) return out_error;
    if (out_args.items.len == 1 and cfg.errOnNoArgs) {
        if (!cfg.verbose) return error.NoArgs;

        if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
        try cfg.writer.?.print("{s}\n", .{ error_message(error.NoArgs).? });

        return error.NoArgs;
    }

    // shrink out_args it because it's guaranteed to be <= args
    if (out_args.items.len < args.vector.len)
        try out_args.resize(allocator, out_args.items.len);

    return .init(allocator, out_args, out_flags);
}

pub const ParseConfig = struct {
    allowDups: bool = false,
    verbose: bool = false,
    writer: ?*std.Io.Writer = null,
    prefix: ?[]const u8 = null,
    allowDashInput: bool = true,
    errOnNoArgs: bool = false,
    exitFirstErr: bool = true,
    delimiter: u8 = ',',
};

/// Returns error messages for select flag errors.
pub fn error_message(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.NoArgs         => "Missing arguments",
        error.NoSuchFlag     => "No such flag",
        error.DuplicateFlag  => "Duplicate flag",
        error.ArgNoArg       => "No argument supplied",
        else                 => null,
    };
}

pub const ParseError = error {
    NoArgs,
    NoSuchFlag,
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-argumentative flag treated as an argumentative
    DuplicateFlag,
    ArgNoArg,           // no argument given to argumentative flag
    NoWriter,
    TypeMismatch,       // failure to retrieve value, type given does not match value
};
