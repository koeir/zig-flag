const std = @import("std");
const root = @import("root.zig");
const helpers = @import("helpers.zig");
const mem = std.mem;
const eql = mem.eql;

pub const FindError = error {
    NoSuchFlag,
    TypeMismatch,
    FlagNotSwitch,
    FlagNotArg,
};

/// Struct for initializing default flags.
/// Also an interface for retrieving `Flag`s for printing and populating look-up table.
pub const Flags = struct {
    const Self = @This();

    list: []const Flag,

    /// Returns null if not found
    pub fn get(self: *const Self, name: []const u8) ?Flag {
        return for (self.list) |flag| {
            if (eql(u8, flag.name, name)) break flag;
        } else null;
    }

    /// Errs if not found
    pub fn tryGet(self: *const Self, name: []const u8) FindError!Flag {
        return for (self.list) |flag| {
            if (eql(u8, flag.name, name)) break flag;
        } else FindError.NoSuchFlag;
    }

    /// Assumes that, if it's a short, is only one char long.
    pub fn getWithFlag(self: *const Self, flag: []const u8) ?Flag {
        return for (self.list) |ret| {
            if (ret.short) |short| {
                if (flag[0] == short) break ret;
            }

            if (ret.long) |long| {
                if (eql(u8, flag, long)) break ret;
            }
        } else null;
    }

    /// Assert value in parameter instead of as a field in the expression
    pub fn getValue(self: *const Self, T: type, name: []const u8) FindError!T {
        const flag = try self.tryGet(name);
        switch (flag.value) {
            inline else => |val| {
                if (@TypeOf(val) != T) return FindError.TypeMismatch;
                return val;
            },
        }
    }

    /// Finds flags in the initialized struct
    pub fn compFind(
        comptime defaults: Self,
        comptime name: []const u8,
    ) Flag {
        comptime {
            for (defaults.list) |flag| {
                if (eql(u8, name, flag.name))
                    return flag;
            } @compileError(name ++ ": Flag not found.");
        }
    }

    /// Retrieves default values from initialized flags
    pub fn compGetValue(
        comptime defaults: Self,
        comptime T: type,
        comptime name: []const u8,
    ) T {
        comptime {
            const default = compFind(name, defaults);
            const val = blk: switch (default.value) {
                inline else => |val| break :blk val,
            };

            if (@TypeOf(val) != T) @compileError("'" ++ name ++ "' Flag is not a type '" ++ @typeName(T) ++ "'");
        }

        switch (defaults.get(name).?.value) {
            inline else => |val| {
                if (@TypeOf(val) != T) unreachable;
                return val;
            },
        }
    }

    pub fn deinit(self: *const Self, allocator: mem.Allocator) void {
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
                if (eql(u8, did, tag)) break true;
            } else false;
            if (already_done) continue;

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
                if (!eql(u8, f.tag orelse continue, tag)) continue;
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

    pub const FlagFmt = enum {
        Long, Short,
    };

    pub const FlagType = enum {
        Switch, Input
    };

    pub const Switch = bool;
    pub const Input = struct {
        const Inner = enum {
            Single, Many
        };

        inner: union(Inner) {
            Single: ?[:0]const u8,
            Many: ?std.ArrayList([]const u8),
        },

        pub fn setArg(self: *Self.Input, allocator: mem.Allocator, arg: [:0]const u8, delimiters: []const u8) !void {
            switch (self.inner) {
                .Many => |*inner| {
                    if (inner.* == null) inner.* = try .initCapacity(allocator, 1);

                    var split = mem.splitAny(u8, arg, delimiters);
                    while (split.next()) |slice| try inner.*.?.append(allocator, slice);
                },
                .Single => |*inner| {
                    inner.* = arg;
                }
            }
        }
    };

    /// Initialization defaults
    pub const Init = struct {
        /// Boolean flag
        pub const SwitchFlag: FlagVal = .{ .Switch = false };

        /// String flag
        pub const InputFlag: FlagVal = .{ .Input = .{ .inner = .{ .Single = null }}};

        /// List of strings flag
        pub const InputFlagMany: FlagVal = .{ .Input = .{ .inner = .{ .Many = null }}};
    };

    pub const FlagVal = union(FlagType) {
        Switch: Switch,                 // On/off
        Input: Input, // Takes an argument

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            switch (self) {
                .Switch => |val| try writer.print("{}", .{ val }),
                .Input => |t| {
                    switch (t) {
                        .Many => |val| {
                            if (val == null) return;

                            for (val.?.items) |arg| {
                                try writer.print("{s}, ", .{ arg });
                            }
                        },
                        .Single => |val| {
                            if (val == null) return;
                            try writer.print("{s}", .{ val.? });
                        }
                    }
                }
            }
        }
    };


    name:   []const u8,
    tag:    ?[]const u8 = null,
    long:   ?[]const u8 = null,
    short:  ?u8 = null,
    value:  FlagVal = .{ .Switch = false },
    /// Only for show in prints, overrides long and short
    vanity: ?[]const u8 = null,
    desc:   ?[]const u8 = null,

    /// Center padding is calculated by
    /// value - n of chars in "-<s>, --<long>"
    pub const PrintFormat = struct {
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

    pub var fmt = PrintFormat{};

    // Toggles value of Switch type flag
    pub fn toggle(self: *Flag) FindError!void {
        return switch (self.value) {
            .Switch => |*val| val.* = !val.*,
            else => FindError.FlagNotSwitch,
        };
    }

    /// Assumes that default for switch is false, and null for inputs
    pub fn isDefault(self: *const Self) bool {
        return switch (self.value) {
            .Switch => |val| !val,
            .Input => |val| switch (val.inner) {
                inline else => |v| v == null
            }
        };
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
