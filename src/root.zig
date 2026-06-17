const std = @import("std");
const helpers = @import("helpers.zig");

const mem = std.mem;

pub const Type = @import("Type.zig");
pub const flagfmt = helpers.flagfmt;

// Memory returned must be freed
pub fn parse(
    allocator: mem.Allocator,
    args: std.process.Args,
    comptime defaults: Type.Flags,
    cfg: ParseConfig,
) !Type.ParsedResult(defaults) {
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

    var errs : ?*std.ArrayList(ParseErrorPackage) = try allocator.create(std.ArrayList(ParseErrorPackage));
    errs.?.* = try std.ArrayList(ParseErrorPackage).initCapacity(allocator, 1);
    errdefer if (errs) |*e| {
        e.*.deinit(allocator);
        allocator.destroy(e.*);
    };

    while (iter.next()) |arg| {
        var didErr = false;

        const fmt: Type.FlagFmt = helpers.flagfmt(arg) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice
            try out_args.append(allocator, arg);
            continue;
        };

        // Slice out dashes
        switch (fmt) {
            .Long   => helpers.parse_flag(allocator, arg[2..], fmt, out_flags, &iter, cfg) catch |err| {
                didErr = true;

                try errs.?.append(allocator, .{
                    .cause = try allocator.dupe(u8, arg),
                    .err = err
                });
            },
            // Iterate through each char
            .Short  => for (arg[1..]) |c| {
                helpers.parse_flag(allocator, &[_]u8 {c}, fmt, out_flags, &iter, cfg) catch |err| {
                didErr = true;

                    const cause: []const u8 = try mem.concat(allocator, u8, &.{
                        "-", &.{c}
                    });

                    try errs.?.append(allocator, .{
                        .cause = cause,
                        .err = err,
                    });
                };
            },
        }

        if (didErr and cfg.exitFirstErr) return .{ 
            .errs = errs, 
            .results = null 
        };
    }

    if (errs.?.items.len < 1) errs = null;
    if (out_args.items.len == 1 and cfg.errOnNoArgs) return error.NoArgs;

    // shrink out_args it because it's guaranteed to be <= args
    if (out_args.items.len < args.vector.len)
        try out_args.resize(allocator, out_args.items.len);

    return .init(allocator, out_args, out_flags, errs);
}

pub const ParseConfig = struct {
    allowDups: bool = false,
    allowDashInput: bool = true,
    errOnNoArgs: bool = false,
    exitFirstErr: bool = true,
    delimiters: []const u8 = ",",
};

pub const ParseErrorPackage = struct {
    err: anyerror,
    cause: []const u8,
};

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
