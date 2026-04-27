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

    // Initialize the parsed flags
    var out_flags = try allocator.alloc(Type.Flag, defaults.list.len);
    errdefer allocator.free(out_flags);
    for (defaults.list, 0..) |*value, i| {
        out_flags[i] = value.*;
        out_flags[i].default = value;
    }

    var out_args: ?std.ArrayList([:0]const u8) = null;
    errdefer if (out_args) |*a| a.deinit(allocator);

    var isErred = false;
    var out_error: anyerror = undefined;
    var arg_count: usize = 0;
    if (!iter.skip()) return error.NoArgs;
    while (iter.next()) |arg| {
        arg_count += 1;
        const fmt: Type.FlagFmt = flagfmt(arg) orelse {
            // If it isn't a flag, add it to out_args and continue
            //
            // note that if the current flag is an argumentative,
            // it takes the next arg, which wouldn't go into this
            // slice

            if (out_args) |*oargs| { try oargs.append(allocator, arg); }
            else {
                out_args = try
                .initCapacity(allocator, args.vector.len);

                try out_args.?.append(allocator, arg);
            }

            continue;
        };

        switch (fmt) {
            .Long   => {
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
                    errptr.* = arg[2..];
                    if (cfg.exitFirstErr) return err;
                };
            },
            .Short  => {
                for (arg[1..], 1..) |c, i| {
                    helpers.parse_flag(
                        allocator,
                        &[_]u8 {c}, fmt,
                        out_flags, &iter,
                        cfg
                    ) catch |err| {
                        isErred = true;
                        if (cfg.verbose){
                            if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
                            try cfg.writer.?.print("-{c}: {s}\n", .{
                                c, error_message(err) orelse @errorName(err) });
                        }

                        out_error = err;
                        errptr.* = arg[i..i+1];
                        if (cfg.exitFirstErr) return err;
                    };
                }
            },
        }
    }

    if (isErred) return out_error;
    if (arg_count == 0 and cfg.errOnNoArgs) {
        if (!cfg.verbose) return error.NoArgs;

        if (cfg.prefix) |prefix| try cfg.writer.?.writeAll(prefix);
        try cfg.writer.?.print("{s}\n", .{ error_message(error.NoArgs).? });

        return error.NoArgs;
    }

    blk: {
    // shrink out_args it because it's guaranteed to be <= args
        if (out_args) |*oargs| {
            if (oargs.items.len == args.vector.len) break :blk;
            try oargs.resize(allocator, oargs.items.len);
    }}

    const ret: Type.Flags = .{
        .list = out_flags,
    };

    return .{
        .flags = ret,
        .flags_array = out_flags,
        .argv = if (out_args) |*oargs| oargs else null };
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
pub fn error_message(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.NoArgs         => "Missing arguments",
        error.NoSuchFlag     => "No such flag",
        error.DuplicateFlag  => "Duplicate flag",
        error.ArgNoArg       => "No argument supplied",
        else                 => null,
    };
}

pub fn constructFlags(comptime defaults: Type.Flags) type {
    comptime var field_names: [defaults.list.len][]const u8 = undefined;
    comptime var field_types: [defaults.list.len]type = undefined;
    comptime var field_attrs: [defaults.list.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (defaults.list, 0..) |value, i| {
        const T = switch (value.value) {
            .Input => ?[][:0]const u8,
            .Switch => bool,
        };

        field_names[i] = value.name;
        field_types[i] = T;
        field_attrs[i] = .{
            .@"align" = @alignOf(T),
        };
    }

    return @Struct(
        .auto, null, &field_names, &field_types, &field_attrs);
}

pub fn populateStruct(comptime flagStruct: anytype, flags: Type.Flags) !flagStruct {
    var ret: flagStruct = undefined;
    inline for (std.meta.fields(flagStruct)) |f| {
        @field(ret, f.name) = sw: switch (f.type) {
            bool => try flags.getValue(Type.Switch, f.name),
            ?[][:0]const u8 => {
                const val = try flags.getValue(Type.Input, f.name);
                break :sw if (val) |v| v.items else null;
            },
            inline else => @compileError("Invalid type during struct population.")
        };
    }

    return ret;
}
