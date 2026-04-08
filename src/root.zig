const std = @import("std");

pub const FlagErrs = error {
    NoSuchFlag,
    FlagNotSwitch,
    FlagNotArg,
    DuplicateFlag,
    IncorrectArrSize
};

const FlagFmt = enum {
    Long, Short,
};

const FlagType = enum {
    Switch, Argumentative
};

const FlagVal = union(FlagType) {
    Switch: bool,
    Argumentative: []const u8,
};

pub const Flags = struct {
    const Self = @This();

    list: []const Flag,
    
    // returns null if not found
    pub fn get(self: *const Self, name: []const u8) ?*const Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else null;
    }

    // errs if not found
    pub fn try_get(self: *const Self, name: []const u8) FlagErrs!*const Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else FlagErrs.NoSuchFlag;
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        for (self.list) |flag| {
            try writer.print("{f}\n", .{ flag } );
        }
    }
};

pub const Flag = struct {
    const Self = @This();

    name:   []const u8,
    long:   ?[]const u8,
    short:  ?u8,
    value:  FlagVal,
    desc:   ?[]const u8,

    // Toggles value of Switch type flag
    pub fn toggle(self: *Flag) !void {
        switch (self.value) {
            .Switch => |*val| val.* = !val.*,
            else    => |_| return FlagErrs.FlagNotSwitch,
        }
    }

    // Sets argument for Argumentative type flag
    // Caller owns memory
    // WIP
    pub fn set_arg(self: *Self, allocator: std.mem.Allocator, arg: []const u8) ![]const u8 {
        switch (self.value) {
            .Argumentative => |*val| {
                 val.* = try allocator.dupe(u8, arg);
                return val.*;
            },
            else           => |_| return FlagErrs.FlagNotArg,
        }
    }

    pub fn isDefault(self: *const Self, defaults: Flags) !bool {
        const default = try defaults.try_get(self.name);

        switch (self.value) {
            .Switch => |val| {
                return (val == default.value.Switch);
            },

            .Argumentative => |val| {
                return std.mem.eql(u8, val, default.value.Argumentative);
            },
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        var padding: usize = 20;

        if (self.short) |short| {
            try writer.print("-{c}", .{ short });
            padding -= 2;

            if (self.long) |_| {
                try writer.writeAll(", ");
                padding -= 2;
            }
        }

        if (self.long) |long| {
            try writer.print("--{s}", .{ long });
            padding -= long.len + 2;
        }

        while (padding > 0) : (padding -= 1) {
            try writer.writeAll(" ");
        }

        if (self.desc) |desc| try writer.writeAll(desc);
    }
};

pub const ParseConfig = struct {
    AllowDups: bool = false,
    verbose: bool = false,
};

pub fn parse(
    args: *std.process.ArgIteratorPosix,
    comptime init_flags: Flags,
    out_flags: []Flag,
    comptime cfg: ParseConfig,
    ) !Flags {

    // Should be compile error really but out_flags must be a runtime var
    if (out_flags.len != init_flags.list.len) {
        @panic("Size of parse result array must match size of init flags array");
    }

    for (init_flags.list, 0..) |value, i| {
        out_flags[i] = value;
    }

    while (args.next()) |arg| {
        const fmt: FlagFmt = flagfmt(arg) orelse continue;

        switch (fmt) {
            .Short => try parse_chain(arg[1..], out_flags, init_flags, cfg),
            .Long => try parse_long(arg[2..], out_flags, init_flags, cfg),
        }
    }

    // Reset the iterator 
    args.index = 0;
    return Flags {
        .list = out_flags
    };
}

// Finds and sets the values for flags that have been called in long form
fn parse_long(arg: []const u8, flags: []Flag, defaults: Flags, cfg: ParseConfig) !void {
    var flag: *Flag = try get_long_flag(flags, arg);

    switch (flag.value) {
        .Switch => |val| {
            if (val != defaults.get(flag.name).?.value.Switch) {
                if (cfg.AllowDups) return;
                if (cfg.verbose) std.debug.print("{}: {s}\n", .{ FlagErrs.DuplicateFlag, arg });
                return;
            }

            try flag.toggle();
        },

        .Argumentative => return, //debug
    }
}

// Same thing but for short flags + chained
fn parse_chain(chain: []const u8, flags: []Flag, defaults: Flags, cfg: ParseConfig) !void {
    for (chain) |c| {
        var flag: *Flag = try get_short_flag(flags, c);

        switch (flag.value) {
            .Switch => |val| {
                if (val != defaults.get(flag.name).?.value.Switch) {
                    if (cfg.AllowDups) continue;
                    if (cfg.verbose) std.debug.print("{}: {c}\n", .{ FlagErrs.DuplicateFlag, c });
                    continue;
                }

                try flag.toggle();
            },

            .Argumentative => continue, //debug
        }
    }
}

// Returns whether if a flag is in long or short form
// null if it is not a flag
fn flagfmt(arg: []const u8) ?FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return FlagFmt.Long;
    return FlagFmt.Short;
}

fn get_long_flag(flags: []Flag, arg: []const u8) FlagErrs!*Flag {
    for (flags) |*flag| {
        if (std.mem.eql(u8, flag.long orelse continue, arg)) return flag;
    }

    return FlagErrs.NoSuchFlag;
}

fn get_short_flag(flags: []Flag, arg: u8) FlagErrs!*Flag {
    for (flags) |*flag| {
        if (arg == flag.short orelse continue) return flag;
    }

    return FlagErrs.NoSuchFlag;
}
