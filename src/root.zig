const std = @import("std");

pub const FlagErrs = error {
    NoSuchFlag,
};

const FlagFmt = enum {
    Long, Short,
};

pub const FlagType = enum {
    Switch, Argumentative
};

pub const FlagVal = union(FlagType) {
    Switch: bool,
    Argumentative: []u8,
};

pub const Flag = struct {
    long:   ?[]const u8,
    short:  ?u8,
    value:  FlagVal,
    opt:    bool,
    desc:   ?[]const u8,

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
    flags: anytype, 
    comptime T: type) !T {
    while (args.next()) |arg| {
        const fmt: FlagFmt = flagfmt(arg) orelse continue;

        const flag: []const u8 = switch (fmt) {
            // Slice to omit '--' and '-'
            .Long   => try get_long_flag(flags, arg[2..]),
            .Short  => try get_short_flag(flags, arg[1..]),
        };

        _ = flag; // debug
    }

    return T{};
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
        if (std.mem.eql(u8, arg, long)) return decls.name;
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

// Make a mutable copy of the initialized flags so that
// they can be used in runtime
//
// Turns declarations from the init flags into fields
pub fn init(comptime init_flags: anytype) type {
    const init_flags_info = @typeInfo(init_flags).@"struct";

    var mut_flags: [init_flags_info.decls.len]std.builtin.Type.StructField = undefined;
    
    inline for (init_flags_info.decls, 0..) |decl, i| {
        const decl_field: Flag = @field(init_flags, decl.name);

        mut_flags[i] = std.builtin.Type.StructField {
            .name = decl.name,
            .type = @TypeOf(decl_field),
            .default_value_ptr = &decl_field,
            .is_comptime = false,
            .alignment = @alignOf(@TypeOf(init_flags)),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &mut_flags,
            .decls = &[_]std.builtin.Type.Declaration {},
            .is_tuple = false,
        }
    });
}
