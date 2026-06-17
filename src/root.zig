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
    const out_flags = try allocator.dupe(Type.Flag, defaults.list);
    errdefer allocator.free(out_flags);

    var out_args = try allocator.create(std.ArrayList([:0]const u8));
    out_args.* = try .initCapacity(allocator, args.vector.len);
    errdefer {
        // deinit and destroy pointer
        out_args.deinit(allocator);
        allocator.destroy(out_args);
    }

    var errs = try allocator.create(std.ArrayList(ParseErrorPackage));
    errs.* = try .initCapacity(allocator, args.vector.len);
    errdefer {
        // deinit and destroy pointer
        errs.deinit(allocator);
        allocator.destroy(errs);
    }

    defer if (errs.items.len > 0) {
        // If returning error, free dis
        allocator.free(out_flags);
        out_args.deinit(allocator);
        allocator.destroy(out_args);
    } else { 
        // else free errors
        errs.deinit(allocator);
        allocator.destroy(errs);
    };

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

        // Slice out dashes
        switch (fmt) {
            .Long   => helpers.parse_flag(allocator, arg[2..], fmt, out_flags, &iter, cfg) catch |err| {
                try errs.append(allocator, .{
                    .cause = try allocator.dupe(u8, arg),
                    .err = err
                });
            },
            // Iterate through each char
            .Short  => for (arg[1..]) |c| {
                helpers.parse_flag(allocator, &[_]u8 {c}, fmt, out_flags, &iter, cfg) catch |err| {
                    const cause = try mem.concat(allocator, u8, &.{
                        "-", &.{c}
                    });

                    try errs.append(allocator, .{
                        .cause = cause,
                        .err = err,
                    });
                };
            },
        }

        if (errs.items.len > 0 and cfg.exitFirstErr) 
            return .{ .Err = errs };
    }

    // Return errs
    if (errs.items.len > 0) return .{ .Err = errs };
    if (out_args.items.len == 1 and cfg.errOnNoArgs) return error.NoArgs;

    // shrink out_args it because it's guaranteed to be <= args
    if (out_args.items.len < args.vector.len)
        try out_args.resize(allocator, out_args.items.len);

    // Return successful
    return .init(allocator, out_args, out_flags);
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
