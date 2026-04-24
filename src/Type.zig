const std = @import("std");
const root = @import("root.zig");

// Init struct for simpler syntax
pub const OutArgs = struct {
    args: ?[][:0]const u8 = null,
    index: usize = 0,

    pub fn add_arg(
        self: *@This(),
        a: std.mem.Allocator,
        arg: [:0]const u8,
        og_arglist: std.process.Args,
    ) !void {
        // Allocate memory if it doesn't exist yet
        if (self.args == null) {
            self.args = try a.alloc([:0]const u8, og_arglist.vector.len);
        }

        self.args.?[self.index] = arg;
        self.index += 1;
    }

    pub fn resize(
        self: *@This(),
        a: std.mem.Allocator
    ) !void {
        if (self.args) |*value| {
            value.* = try a.realloc(value.*, self.count());
        }
    }

    pub fn count(self: *@This()) usize {
        if (self.args == null) return 0;

        return self.index;
    }
};

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
pub const Switch = bool;
pub const Argumentative = ?[:0]const u8;

pub const FlagType = enum {
    Switch, Argumentative
};

pub const ParseResult = struct {
    flags: Flags,
    argv: ?[][:0]const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        args: std.process.Args,
        comptime init_flags: Flags,
        errptr: *?[*:0]const u8,
        cfg: ParseConfig
    ) !ParseResult {
        return try root.parse(allocator, args, init_flags, errptr, cfg);
    }

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.flags.list);
        allocator.free(self.argv orelse return);
    }
};

pub const FlagVal = union(FlagType) {
    Switch: bool,                 // On/off
    Argumentative: ?[:0]const u8, // Takes an argument

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .Switch => |val| try writer.print("{}", .{ val }),
            .Argumentative => |val| try writer.print("{s}", .{ val.? }),
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
    pub fn try_get(self: *const Self, name: []const u8) FlagError!*const Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break &flag;
        } else FlagError.NoSuchFlag;
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

    pub fn get_value(self: *const Self, name: []const u8, comptime T: type) FlagError!T {
        const flag = try try_get(self, name);

        // looks ugly but is stupidly necessary to be hardwritten
        // repetitively as of Zig 0.16.0 i think
        switch (flag.value) {
            .Switch => |val| {
                if (@TypeOf(val) != T) {
                    return FlagError.TypeMismatch;
                } return val;
            },
            .Argumentative => |val| {
                if (@TypeOf(val) != T) {
                    return FlagError.TypeMismatch;
                } return val;
            }
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
            brackets, colon
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

            for (0..cfg.padding_left) |_| {
                try writer.writeAll(" ");
            }

            // print all flags of the tag
            switch (cfg.tagStyle) {
                .colon    => try writer.print("{s}:\n", .{ tag }),
                .brackets => try writer.print("[{s}]\n", .{ tag }),
            }

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
    isVanity: bool = false, // only for show in prints
    desc:   ?[]const u8 = null,
    default: *const Flag = undefined,

    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    pub const Format = struct {
        style: u8 = ' ',
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
        switch (self.value) {
            .Switch => |*val| val.* = !val.*,
            else    => return FlagError.FlagNotSwitch,
        }
    }

    pub fn set_arg(self: *Flag, arg: [:0]const u8) !void {
        switch (self.value) {
            .Switch => return FlagError.FlagNotArg,
            .Argumentative => |*val| {
                val.* = arg;
            }
        }
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
            .Argumentative => |val| {
                switch (self.default.value) {
                    .Argumentative => |default| {
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

        if (self.short) |short| {
            try writer.print("-{c}", .{ short });
            minus += "-.".len;

            switch (self.value) {
                .Argumentative => {
                    try writer.print(" <{s}>", .{ self.name });
                    minus += self.name.len + " <>".len;
                },
                else => {},
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
            switch (self.value) {
                .Argumentative => {
                    try writer.print(" <{s}>", .{ self.name });
                    minus += self.name.len + " <>".len;
                },
                else => {},
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
        for (0..padding_left) |_| {
            try writer.writeAll(&[_]u8{fmt.style});
        }

        for (self.desc orelse return) |c| {
            try writer.print("{c}", .{c});
            if (c == '\n') {
                for (0..padding_left) |_|
                    try writer.writeAll(" ");
            }
        } try writer.writeAll("\n");
    }

    fn format_twocolumns(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        // Don't change the actual padding var
        const padding = fmt.padding;
        const minus = try self.print_flags(padding.left, writer);

        if (padding.center < minus) @panic("Need more center-padding!");

        for (0..padding.center-minus-1) |_| {
            try writer.writeAll(&[_]u8 { fmt.style });
        } try writer.writeAll(" ");

        for (self.desc orelse return) |c| {
            try writer.print("{c}", .{c});
            if (c == '\n') {
                for (0..padding.center+padding.left) |_| try writer.writeAll(" ");
            }
        }
    }
};

pub const ParseConfig = struct {
    allowDups: bool = false,
    verbose: bool = false,
    writer: ?*std.Io.Writer = null,
    prefix: ?[]const u8 = null,
    // very specific
    allowDashAsFirstCharInArgForArg: bool = true,
    errOnNoArgs: bool = false,
    exitFirstErr: bool = true,
};
