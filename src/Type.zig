const std = @import("std");
const root = @import("root.zig");

const eql = std.mem.eql;

pub const FlagError = error {
    NoArgs,
    NoSuchFlag,
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-argumentative flag treated as an argumentative
    DuplicateFlag,
    ArgNoArg,           // no argument given to argumentative flag
    NoWriter,
    TypeMismatch,       // failure to retrieve value, type given does not match value
};

pub const FlagFmt = enum {
    Long, Short,
};

// Type aliases
pub const SwitchFlag: FlagVal = .{ .Switch = false };
pub const InputFlag: FlagVal = .{ .Input = null };

pub const Switch = bool;
pub const Input = ?[:0]const u8;

pub const FlagType = enum {
    Switch, Input
};

pub const ParseResult = struct {
    flags: Flags,
    argv: ?std.ArrayList([:0]const u8),

    pub fn init(
        allocator: std.mem.Allocator,
        args: std.process.Args,
        comptime init_flags: Flags,
        errptr: *?[*:0]const u8,
        cfg: ParseConfig
    ) !ParseResult {
        return try root.parse(allocator, args, init_flags, errptr, cfg);
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.flags.deinit(allocator);
        if (self.argv) |*args| args.deinit(allocator);
    }
};

pub const FlagVal = union(FlagType) {
    Switch: bool,                 // On/off
    Input: ?[:0]const u8, // Takes an argument

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .Switch => |val| try writer.print("{}", .{ val }),
            .Input => |val| try writer.print("{s}", .{ val.? }),
        }
    }
};

pub const ArgIterator = struct {
    args: std.process.Args,
    // vvv Should not be used for iterating as it does not update index
    iter: *std.process.Args.Iterator,
    // ^^^
    index: usize = 0,
    count: usize,

    pub fn current(self: *@This()) ?[:0]const u8 {
        if (self.index > self.count) return null;

        if (self.index == 0) return std.mem.span(self.args.vector[self.index]);

        return std.mem.span(self.args.vector[self.index-1]);
    }

    pub fn next(self: *@This()) ?[:0]const u8 {
        if (self.index == self.count) return null;

        self.index += 1;
        return self.iter.next();
    }

    pub fn skip(self: *@This()) bool {
        if (self.index == self.count) return false;

        self.index += 1;
        return self.iter.skip();
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
    pub fn tryGet(self: *const Self, name: []const u8) FlagError!*const Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else FlagError.NoSuchFlag;
    }

    pub fn getWithFlag(self: *const Self, flag: []const u8) ?*const Flag {
        return for (self.list) |*ret| {
            if (ret.short) |short| {
                if (flag[0] == short) break ret;
            }

            if (ret.long) |long| {
                if (std.mem.eql(u8, flag, long)) break ret;
            }
        } else null;
    }

    pub fn getValue(self: *const Self, T: type, name: []const u8) FlagError!T {
        const flag = try self.tryGet(name);
        switch (flag.value) {
            inline else => |val| {
                if (@TypeOf(val) != T) return FlagError.TypeMismatch;
                return val;
            },
        }
    }

    // Checks if flag exists at comptime
    pub fn compFind(
        comptime name: []const u8,
        comptime defaults: Flags
    ) *const Flag {
        comptime { 
            for (defaults.list) |*flag| {
                if (std.mem.eql(u8, name, flag.name))
                    return flag;
            } @compileError(name ++ ": Flag not found.");
        }
    }

    // Checks at comptime if flag exists first, then gets it if it does.
    pub fn compGet(
        self: *const Self,
        comptime name: []const u8,
        comptime defaults: Flags
    ) *const Flag {
        _ = comptime compFind(name, defaults);
        return self.get(name).?;
    }

    pub fn compGetValue(
        self: *const Self,
        comptime T: type,
        comptime name: []const u8,
        comptime defaults: Flags
    ) T {
        comptime {
            const default = compFind(name, defaults);
            const val = blk: switch (default.value) {
                inline else => |val| break :blk val,
            };

            if (@TypeOf(val) != T) @compileError("'" ++ name ++ "' Flag is not a type '" ++ @typeName(T) ++ "'");
        }

        switch (self.get(name).?.value) {
            inline else => |val| {
                if (@TypeOf(val) != T) unreachable;
                return val;
            },
        }
    }

    pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
        allocator.free(self.list);
    }

    pub const UsageConfig = struct {
        padding_left: usize = 0,
        printUntagged: bool = false,
        untaggedFirst: bool = true,
        tagStyle: enum {
            brackets, colon, underline
        } = .colon
    };

    // can only be called by init flags
    pub fn usage(
        comptime self: @This(),
        writer: *std.Io.Writer,
        cfg: UsageConfig,
    ) std.Io.Writer.Error!void {

        // get n of flags
        const n_tags: usize = comptime blk: {
            var n_tags: usize = 0;
            for (self.list) |flag| {
                if (flag.tag) |_| n_tags += 1;
            } break :blk n_tags;
        };

        // print tagless flags
        if (cfg.untaggedFirst and cfg.printUntagged) try self.printUntagged(writer);

        // keep track of flags that are already printed
        var done: [n_tags][]const u8 = undefined;
        var n_done: usize = 0;
        for (self.list) |flag| {
            const tag = flag.tag orelse continue;

            // if the flags of tag is already printed,
            // continue
            const already_done = for (done) |did| {
                if (std.mem.eql(u8, did, tag)) break true;
            } else false;
            if (already_done) continue;

            // because columns .one already prints newline
            if (Flag.fmt.columns == .two) try writer.writeAll("\n");
            // print padding before tags
            for (0..cfg.padding_left) |_| {
                try writer.writeAll(" ");
            }

            // print tag
            switch (cfg.tagStyle) {
                .colon      => try writer.print("{s}:\n", .{ tag }),
                .brackets   => try writer.print("[{s}]\n", .{ tag }),
                .underline  => try writer.print("\x1b[4m{s}\x1b[0m\n", .{ tag }),
            }

            // print all flags of the tag
            for (self.list) |f| {
                if (!std.mem.eql(u8, f.tag orelse continue, tag)) continue;
                try writer.print("{f}\n", .{ f });
            }

            done[n_done] = tag;
            n_done += 1;
        }

        if (!cfg.untaggedFirst and cfg.printUntagged) try self.printUntagged(writer);
    }

    fn printUntagged(self: @This(), writer: *std.Io.Writer) !void {
        var hasUntagged = false;
        for (self.list) |flag| {
            if (flag.tag) |_| continue;
            try writer.print("{f}\n", .{ flag });
            hasUntagged = true;
        }

        if (hasUntagged) try writer.writeAll("\n");
    }
};

pub const Flag = struct {
    const Self = @This();

    name:   []const u8,
    tag:    ?[]const u8 = null,
    long:   ?[]const u8 = null,
    short:  ?u8 = null,
    value:  FlagVal,
    vanity: ?[]const u8 = null, // only for show in prints, overrides long and short
    desc:   ?[]const u8 = null,
    default: *const Flag = undefined,

    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    pub const Format = struct {
        fillerStyle: u8 = ' ',
        greyOutFiller: bool = false,
        greyOutDesc: bool = false,
        columns: enum {
            one, two
        } = .two,
        padding: struct {
            left: usize = 1,
            desc_left: usize = 1, // useless for columns.two; applied on top of .left
            center: usize = 30, //useless for columns.one
        } = .{},
    };

    pub var fmt = Format{};

    // Toggles value of Switch type flag
    pub fn toggle(self: *Flag) !void {
        if (self.value == .Switch) {
            self.value.Switch = !self.value.Switch;
        } else return FlagError.FlagNotSwitch;
    }

    pub fn setArg(self: *Flag, arg: [:0]const u8) !void {
        if (self.value == .Input ) {
            self.value.Input = arg;
        } else return FlagError.FlagNotArg;
    }

    // Pass on the init Flags struct
    pub fn isDefault(self: *const Self) bool {
        switch (self.value) {
            .Switch => |val| {
                switch (self.default.value) {
                    .Switch => |default| {
                        return val == default;
                    },
                    else    => unreachable,
                }
            },
            .Input => |val| {
                switch (self.default.value) {
                    .Input => |default| {
                        if (val) |v| {
                            if (default) |d| {
                                return std.mem.eql(u8, v, d);
                            } else return false;
                        } else {
                            if (default == null) {
                                return true;
                            } else return false;
                        }
                    },
                    else    => unreachable,
                }
            },
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (fmt.columns) {
            .one => try format_onecolumn(self, writer),
            .two => try format_twocolumns(self, writer),
        }
    }

    // returns number of chars printed
    fn print_flags(
        self: @This(),
        padding_left: usize,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!usize {
        var minus: usize = 0;

        for (0..padding_left) |_| {
            try writer.writeAll(" ");
        }

        // overwrite flags with vanity if it exists
        if (self.vanity) |v| {
            try writer.writeAll(v);
            return v.len;
        }

        if (self.short) |short| {
            try writer.print("-{c}", .{ short });
            minus += "-.".len;

            if (self.value == .Input) {
                try writer.print(" <{s}>", .{ self.name });
                minus += self.name.len + " <>".len;
            }

            if (self.long) |_| {
                try writer.writeAll(", ");
                minus += ", ".len;
            }
        } else {
            try writer.writeAll("    ");
            minus += "-., ".len;
        }

        if (self.long) |long| {
            try writer.print("--{s}", .{ long });
            if (self.value == .Input ) {
                    try writer.print(" <{s}>", .{ self.name });
                    minus += self.name.len + " <>".len;
            }
            minus += long.len + "--".len;
        }

        return minus;
    }

    fn format_onecolumn(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        const padding = fmt.padding;
        _ = try self.print_flags(padding.left, writer);

        const padding_left = padding.left + padding.desc_left - 1;

        try writer.writeAll("\n");
        if (fmt.greyOutFiller) try writer.writeAll("\x1b[90m");
        for (0..padding_left) |_| {
            try writer.writeAll(&[_]u8{fmt.fillerStyle});
        } if (fmt.greyOutFiller) try writer.writeAll("\x1b[0m");

        if (fmt.greyOutDesc) try writer.writeAll("\x1b[90m");
        for (self.desc orelse return) |c| {
            try writer.print("{c}", .{c});
            if (c == '\n') {
                for (0..padding_left) |_|
                    try writer.writeAll(" ");
            }
        } if (fmt.greyOutDesc) try writer.writeAll("\x1b[0m");
        try writer.writeAll("\n");
    }

    fn format_twocolumns(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        // Don't change the actual padding var
        const padding = fmt.padding;
        const minus = try self.print_flags(padding.left, writer);

        if (padding.center < minus) @panic("Need more center-padding!");

        if (fmt.greyOutFiller) try writer.writeAll("\x1b[90m");
        for (0..padding.center-minus-1) |_| {
            try writer.writeAll(&[_]u8 { fmt.fillerStyle });
        } try writer.writeAll(" ");
        if (fmt.greyOutFiller) try writer.writeAll("\x1b[0m");

        if (fmt.greyOutDesc) try writer.writeAll("\x1b[90m");
        for (self.desc orelse return) |c| {
            try writer.print("{c}", .{c});
            if (c == '\n') {
                for (0..padding.center+padding.left) |_| try writer.writeAll(" ");
            }
        } if (fmt.greyOutDesc) try writer.writeAll("\x1b[0m");
    }
};

pub const ParseConfig = struct {
    allowDups: bool = false,
    verbose: bool = false,
    writer: ?*std.Io.Writer = null,
    prefix: ?[]const u8 = null,
    // very specific
    allowDashInput: bool = true,
    errOnNoArgs: bool = false,
    exitFirstErr: bool = true,
};
