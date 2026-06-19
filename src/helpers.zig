const std = @import("std");
const root = @import("root.zig");
const mem = std.mem;

const Type = root.Type;
const Flag = Type.Flag;
const Flags = Type.Flags;
const ParseError = root.Parse.ParseError;

pub fn parse_flag(
    allocator: mem.Allocator,
    arg: []const u8,
    fmt : root.Type.Flag.FlagFmt,
    flags: []Flag,
    args: *std.process.Args.Iterator,
    cfg: root.Parse.ParseConfig
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
            (!isInputType or flag.value.Input.inner != .Many))
                return ParseError.DuplicateFlag;
    }

    switch (flag.value) {
        .Input => {
            const next_arg = args.next() orelse {
                return ParseError.ArgNoArg;
            };

            if (next_arg[0] == '-' and !cfg.allowDashInput) {
                return ParseError.ArgNoArg;
            }

            try flag.value.Input.setArg(allocator, next_arg, cfg.delimiters);
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
        if (mem.eql(u8, flag.long orelse continue, arg)) return flag;
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

/// Populate look-up table made with StructFlags with parsed flags/arguments.
/// A hashmap is used just for cleaner code. The hashmap is deinitialized right after parsing flags.
pub fn populateStruct(comptime flagStruct: anytype, flags: std.StringHashMap(Type.Flag)) !flagStruct {
    var ret: flagStruct = undefined;
    inline for (std.meta.fields(flagStruct)) |f| {
        @field(ret, f.name) = sw: switch (f.type) {
            bool            => flags.get(f.name).?.value.Switch,
            ?[:0]const u8   => break :sw flags.get(f.name).?.value.Input.inner.Single,
            ?[][]const u8   => break :sw if (flags.get(f.name).?.value.Input.inner.Many) |v| v.items else null,
            inline else     => @compileError("Invalid type during struct population.")
        };
    }

    return ret;
}

/// Returns whether if a flag is in long or short form.
/// Rerurns _null_ if it is not a flag.
pub fn flagfmt(arg: []const u8) ?Type.Flag.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.Flag.FlagFmt.Long;
    return Type.Flag.FlagFmt.Short;
}
