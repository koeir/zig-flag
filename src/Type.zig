const std = @import("std");
const root = @import("root.zig");

pub const FlagErrs = error {
    NoArgs,
    NoSuchFlag,
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-argumentative flag treated as an argumentative
    DuplicateFlag,
    ArgNoArg,           // no argument given to argumentative flag
    ArgTooLong,
};

pub const FlagFmt = enum {
    Long, Short,
};

pub const FlagType = enum {
    Switch, Argumentative
};

pub const FlagVal = union(FlagType) {
    Switch: bool,                   // On/off
    Argumentative: [1024:0]u8, // Takes an argument
    
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .Switch => |val| try writer.print("{}", .{ val }),
            .Argumentative => |val| try writer.print("{s}", .{ val }),
        }
    }
};

// This is just a view into a list of immut flags.
// This is meant to hold either the default flags or the already parsed flags;ty
// type should not and cannot be used for mutation
//
// if mutation after parsing is necessary for some reason,
// the empty flag array made on the stack can be used
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

    pub fn get_with_flag(self: *const Self, flag: []const u8) ?*const Flag {
        return for (self.list) |*ret| {
            if (ret.short) |short| {
                if (flag[0] == short) break ret;
            }

            if (ret.long) |long| {
                if (std.mem.eql(u8, flag, long)) break ret;
            }
        } else null;
    }

    pub fn get_value(self: *const Self, comptime name: []const u8, comptime T: type) FlagErrs!T {
        const flag = try try_get(self, name);

        return switch (flag.value) {
            .Switch => |val| {
                if (@TypeOf(val) != T) { 
                    @panic(
                        "type provided does not match the retrieved flag's type\n" ++
                        "hint: tried to retrieve the value of '" ++ name ++ "' as '" ++ @typeName(T) ++
                        "' when '" ++ name ++ "' is '" ++ @typeName(@TypeOf(val)) ++ "'"
                    ); 
                }
                return val;
            },
            .Argumentative => |val| {
                if (@TypeOf(val) != T) { 
                    @panic(
                        "type provided does not match the retrieved flag's type\n" ++
                        "hint: tried to retrieve the value of '" ++ name ++ "' as '" ++ @typeName(T) ++
                        "' when '" ++ name ++ "' is '" ++ @typeName(@TypeOf(val)) ++ "'"
                    ); 
                }
                return val;
            }
        };
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
    long:   ?[]const u8 = null,
    short:  ?u8 = null,
    value:  FlagVal,
    desc:   ?[]const u8 = null,

    pub var padding: u64 = 30;

    // Toggles value of Switch type flag
    pub fn toggle(self: *Flag) !void {
        switch (self.value) {
            .Switch => |*val| val.* = !val.*,
            else    => |_| return FlagErrs.FlagNotSwitch,
        }
    }

    pub fn set_arg(self: *Flag, arg: []const u8) !void {
        switch (self.value) {
            .Switch => |_| return FlagErrs.FlagNotArg,
            .Argumentative => |*val| {
                if (arg.len > 1024) return FlagErrs.ArgTooLong;
                @memcpy(val[0..arg.len], arg);
            }
        }
    }

    // Pass on the init Flags struct
    pub fn isDefault(self: *const Self, comptime defaults: Flags) !bool {
        const default = try defaults.try_get(self.name);

        switch (self.value) {
            .Switch => |val| {
                return (val == default.value.Switch);
            },

            .Argumentative => |val| {
                const default_val: []const u8 =  switch (default.value) {
                    .Argumentative => |v| &v,
                    else => unreachable,
                };

                return std.mem.eql(u8, &val, default_val);
            },
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        // Don't change the actual padding var
        var tmp_padding = padding;

        if (self.short) |short| {
            try writer.print("-{c}", .{ short });
            tmp_padding -= 2;

            switch (self.value) {
                .Argumentative => {
                    try writer.print(" <{s}>", .{ self.name });
                    tmp_padding -= @as(u64, self.name.len) + 3;
                },
                else => {},
            }

            if (self.long) |_| {
                try writer.writeAll(", ");
                tmp_padding -= 2;
            }
        } else {
            try writer.writeAll("    ");
            tmp_padding -= 4;
        }

        if (self.long) |long| {
            try writer.print("--{s}", .{ long });
            switch (self.value) {
                .Argumentative => {
                    try writer.print(" <{s}>", .{ self.name });
                    tmp_padding -= @as(u64, self.name.len) + 3;
                },
                else => {},
            }
            tmp_padding -= @as(u64, long.len + 2);
        }

        while (tmp_padding > 0) : (tmp_padding-= 1) {
            try writer.writeAll(" ");
        }

        if (self.desc) |desc| try writer.writeAll(desc);
    }
};

pub const ParseConfig = struct {
    allowDups: bool = false,
    verbose: bool = false,
    writer: ?*std.io.Writer = null,
    // very specific
    allowDashAsFirstCharInArgForArg: bool = true,
};
