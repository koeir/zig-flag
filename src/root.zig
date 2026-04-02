const std = @import("std");

pub const FlagErrs = error {
    NoSuchFlag,
};

const FlagFmt = enum {
    Long, Short,
};

const FlagType = enum {
    Switch, Argumentative
};

const FlagVal = union(FlagType) {
    Switch: bool,
    Argumentative: []u8,
};

pub const Flag = struct {
    long:   ?[]const u8,
    short:  ?u8,
    value:  FlagVal,
    opt:    bool,
    desc:   ?[]const u8,
};

pub fn parse(args: *std.process.ArgIteratorPosix, flags: anytype) !void {
    while (args.next()) |arg| {
        const fmt: FlagFmt = flagfmt(arg) orelse continue;

        const flag: []const u8 = switch (fmt) {
            // Slice to omit '--' and '-'
            .Long   => try get_long_flag(flags, arg[2..]),
            .Short  => try get_short_flag(flags, arg[1..]),
        };

        std.debug.print("{s}\n", .{ flag });
    }
}

fn flagfmt(arg: []const u8) ?FlagFmt {
    if (arg.len < 2) return null;
    if (arg[0] != '-') return null;

    if (arg[1] == '-') return FlagFmt.Long;
    return FlagFmt.Short;
}

fn get_long_flag(flags: anytype, arg: []const u8) FlagErrs![]const u8 {
    inline for (@typeInfo(flags).@"struct".decls) |decls| {
        const long: []const u8 = @field(flags, decls.name).@"long" orelse continue;
        if (std.mem.eql(u8, arg, long)) return long;
    }

    return FlagErrs.NoSuchFlag;
} 

// Should be updated to work for flag chains
fn get_short_flag(flags: anytype, arg: []const u8) FlagErrs![]const u8 {
    for (arg) |char| {
        inline for (@typeInfo(flags).@"struct".decls) |decls| {
            const short: u8 = @field(flags, decls.name).@"short" orelse continue;
            if (short == char) {
                return decls.name;
            }
        }
    }

    return FlagErrs.NoSuchFlag;
}
