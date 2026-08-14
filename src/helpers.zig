const std = @import("std");
const root = @import("root.zig");
const mem = std.mem;

const Type = root.Type;
const Flag = Type.Flag;
const ParseError = root.Parse.ParseError;

pub fn parseFlag(
    allocator: mem.Allocator,
    arg: []const u8,
    fmt : root.Type.Flag.FlagFmt,
    flags: Type.RuntimeFlags,
    args: *std.process.Args.Iterator,
    cfg: root.Parse.ParseConfig
) !void {
    const flag = flags.getWithFlag(arg, fmt) orelse
        return ParseError.NoSuchFlag;

    // Checks:
    //  if Switch: is false?
    //  if Input:  is null?
    const isDefault = flag.isDefault();
    {
        // If it's not default and not allow dups, return dup flags error
        // many input flags are allowed to have dups
        const isInputType = flag.value == .Input;
        if (!isDefault and !cfg.allowDups and
            (!isInputType or flag.value.Input != .Many))
                return ParseError.DuplicateFlag;
    }

    switch (flag.value) {
        .Input => |*val| {
            const next_arg = args.next() orelse
                return ParseError.MissingInput;

            if (next_arg[0] == '-' and !cfg.allowDashInput)
                return ParseError.MissingInput;

            try val.setArg(allocator, next_arg, cfg.delimiters);
        },

        .Switch => |*val| val.* = true,
    }
}

/// Populate look-up table made with StructFlags with parsed flags/arguments.
/// A hashmap is used just for cleaner code. The hashmap is deinitialized right after parsing flags.
pub fn populateStruct(comptime flagStruct: type, flags: Type.RuntimeFlags) flagStruct {
    var ret: flagStruct = undefined;
    inline for (std.meta.fields(flagStruct)) |f| {
        @field(ret, f.name) = sw: switch (f.type) {
            bool            => flags.get(f.name).?.value.Switch,
            ?[:0]const u8   => break :sw flags.get(f.name).?.value.Input.Single,
            ?[][]const u8   => break :sw if (flags.get(f.name).?.value.Input.Many) |v| v.items else null,
            inline else     => @compileError("Invalid type during struct population.")
        };
    }

    return ret;
}

/// Returns whether if a flag is in long or short form.
/// Rerurns _null_ if it is not a flag.
pub fn flagFmt(arg: []const u8) ?Type.Flag.FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return Type.Flag.FlagFmt.Long;
    return Type.Flag.FlagFmt.Short;
}
