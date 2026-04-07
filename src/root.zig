const std = @import("std");
const root = @This();

pub const FlagErrs = error {
    NoSuchFlag,
    FlagNotSwitch,
    FlagNotArg,
};

const FlagFmt = enum {
    Long, Short,
};

pub const FlagType = enum {
    Switch, Argumentative
};

pub const FlagVal = union(FlagType) {
    Switch: bool,
    Argumentative: []const u8,
};

pub const Flags = struct {
    list: *const []const Flag,
    
    // returns null if not found
    pub fn get(self: *const Flags, name: []const u8) ?*const Flag {
        return for (self.list.*) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else null;
    }

    // errs if not found
    pub fn try_get(self: *const Flags, name: []const u8) FlagErrs!*const Flag {
        return for (self.list.*) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else FlagErrs.NoSuchFlag;
    }
};

pub const Flag = struct {
    name:   []const u8,
    long:   ?[]const u8,
    short:  ?u8,
    value:  FlagVal,
    opt:    bool,
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
    pub fn set_arg(self: *Flag, allocator: std.mem.Allocator, arg: []const u8) ![]const u8 {
        switch (self.value) {
            .Argumentative => |*val| {
                 val.* = try allocator.dupe(u8, arg);
                return val.*;
            },
            else           => |_| return FlagErrs.FlagNotArg,
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

pub fn parse(
    args: *std.process.ArgIteratorPosix,
    init_flags: []const Flag,
    out_flags: []Flag) !Flags {

    for (init_flags, 0..) |f, i| {
        out_flags[i] = f;
    }

    while (args.next()) |arg| {
        const fmt: FlagFmt = flagfmt(arg) orelse continue;

        var flag: *Flag = switch (fmt) {
            // Slice to omit '--' and '-'
            .Long   => try get_long_flag(out_flags, arg[2..]),
            .Short  => try get_short_flag(out_flags, arg[1..]),
        };

        switch (flag.value) {
            .Switch  => try flag.toggle(),
            else => continue,
        }
    }

    return Flags {
        .list = &out_flags,
    };
}

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

// Should be updated to work for flag chains
fn get_short_flag(flags: []Flag, arg: []const u8) FlagErrs!*Flag {
    for (arg) |c| {
        for (flags) |*flag| {
            if (flag.short orelse continue == c) return flag;
        }
    }

    return FlagErrs.NoSuchFlag;
}

// Make a mutable copy of the initialized flags so that
// they can be used in runtime
//
// Turns declarations from the init flags into fields
pub fn init(comptime init_flags: anytype) Flags {
    const init_flags_info = @typeInfo(init_flags).@"struct";

    var flagarr: [init_flags_info.decls.len]Flag = undefined;

    inline for (init_flags_info.decls, 0..) |decl, i| {
        const decl_field = @field(init_flags, decl.name);
        if (@TypeOf(decl_field) != Flag) {
            @compileError("Found declaration in struct of init flags that is not of type Flag");
        }
        flagarr[i] = decl_field;
    }

    return Flags {
        .list = &flagarr,
    };
}
