const std = @import("std");
const root = @import("root");
const helpers = @import("helpers.zig");
const eql = std.mem.eql;

/// Type aliases
pub const Switch = bool;
pub const Input = union(InputType) {
    Single: ?[:0]const u8,
    Many: ?std.ArrayList([:0]const u8),
    OptionalSingle: struct {
        enabled: Switch = false,
        argument: ?[:0]const u8 = null,
    },
    OptionalMany: struct {
        enabled: Switch = false,
        arguments: ?std.ArrayList([:0]const u8) = null,
    },
};

pub const FlagFmt = enum {
    Long, Short,
};

/// Initialization defaults
pub const Init = struct {
    /// Boolean flag
    pub const SwitchFlag: FlagVal = .{ .Switch = false };

    /// String flag
    pub const InputFlag: FlagVal = .{ .Input = .{ .Single = null } };

    /// List of strings flag
    pub const InputFlagMany: FlagVal = .{ .Input = .{ .Many = null } };

    /// Boolean + optional string flag
    pub const InputOptionalFlagSingle: FlagVal = .{ .Input = .{ .OptionalSingle = .{} } };

    /// Boolean + optional list of strings flag
    pub const InputOptionalFlagMany: FlagVal = .{ .Input = .{ .OptionalMany = .{} } };
};

pub const FlagType = enum {
    Switch, Input
};

pub const InputType = enum {
    Many, Single, Optional
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

/// Struct for initializing default flags.
/// Also an interface for retrieving `Flag`s for printing and populating look-up table.
pub const Flags = struct {
    const Self = @This();

    list: []const Flag,

    /// Returns null if not found
    pub fn get(self: *const Self, name: []const u8) ?Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break flag;
        } else null;
    }

    /// Errs if not found
    pub fn tryGet(self: *const Self, name: []const u8) FindError!Flag {
        return for (self.list) |flag| {
            if (std.mem.eql(u8, flag.name, name)) break flag;
        } else FindError.NoSuchFlag;
    }

    pub fn getWithFlag(self: *const Self, flag: []const u8) ?Flag {
        return for (self.list) |ret| {
            if (ret.short) |short| {
                if (flag[0] == short) break ret;
            }

            if (ret.long) |long| {
                if (std.mem.eql(u8, flag, long)) break ret;
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
                if (std.mem.eql(u8, name, flag.name))
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
    value:  FlagVal = .{ .Switch = false },
    /// Only for show in prints, overrides long and short
    vanity: ?[]const u8 = null,
    desc:   ?[]const u8 = null,
    /// A pointer for the `ParseResult`'s `Flags` to the initialized ones
    default: *const Flag = undefined,

    /// Center padding is calculated by
    /// value - n of chars in "-<s>, --<long>"
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
        } else return FindError.FlagNotSwitch;
    }

    pub fn setArg(self: *Flag, allocator: std.mem.Allocator, arg: [:0]const u8) !void {
        if (self.value != .Input ) return FindError.FlagNotArg;

        switch (self.value.Input) {
            .Many => |*inner| {
                if (inner.* == null) inner.* = try .initCapacity(allocator, 1);
                try inner.*.?.append(allocator, arg);
            },
            .Single => |*inner| {
                inner.* = arg;
            }
        }
    }

    // Pass on the init Flags struct
    pub fn isDefault(self: *const Self) bool {
        return switch (self.value) {
            .Switch => |val| !val,
            .Input => |val| switch (val) {
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

pub const ParseConfig = struct {
    allowDups: bool = false,
    verbose: bool = false,
    writer: ?*std.Io.Writer = null,
    prefix: ?[]const u8 = null,
    allowDashInput: bool = true,
    errOnNoArgs: bool = false,
    exitFirstErr: bool = true,
};

/// Constructs and populates results for flagless arg list, flags, allocator, etc.
pub fn ParsedResult(
    comptime defaults: Flags, 
) type {
    return struct {
        const Self = @This();

        argv: [][:0]const u8,
        flags: StructFlags(defaults),
        allocator: std.mem.Allocator,
        inner: struct {
            flags: []Flag,
            argv: *std.ArrayList([:0]const u8),
        },

        pub fn init(
            allocator: std.mem.Allocator,
            argv: *std.ArrayList([:0]const u8), 
            flags_array: []Flag
        ) !Self {
            // Using hashmap for cleaner code in populateStruct
            var parsed: std.StringHashMap(Flag) = .init(allocator);
            defer parsed.deinit();

            for (flags_array) |flag| {
                try parsed.put(flag.name, flag);
            }

            const struct_flags = try helpers.populateStruct(StructFlags(defaults), parsed);

            return .{
                .allocator = allocator,
                .flags = struct_flags,
                .argv = argv.items,
                .inner = .{
                    .argv = argv,
                    .flags = flags_array
                }
            };
        }

        pub fn deinit(self: *const @This()) void {
            for (self.inner.flags) |*flag| {
                if (flag.value != .Input) continue;
                if (flag.value.Input) |*input| input.deinit(self.allocator);
            }

            self.allocator.free(self.inner.flags);
            
            self.inner.argv.deinit(self.allocator);
            self.allocator.destroy(self.inner.argv);
        }
    };
}

/// Initializes a struct/look-up table for holding values of parsed flags/arguments.
/// Essentially simplifies the defaults flag array in comptime to key:value pairs
///
/// Is in public scope for aliasing Flags type in main or whatever
pub fn StructFlags(comptime defaults: Flags) type {
    comptime var field_names: [defaults.list.len][]const u8 = undefined;
    comptime var field_types: [defaults.list.len]type = undefined;
    comptime var field_attrs: [defaults.list.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (defaults.list, 0..) |value, i| {
        const T = switch (value.value) {
            .Input => |in| switch (in) {
                    .Single => ?[:0]const u8,
                    .Many => ?[][:0]const u8 },
            .Switch => bool,
        };

        field_names[i] = value.name;
        field_types[i] = T;
        field_attrs[i] = .{
            .@"align" = @alignOf(T),
        };
    }

    return @Struct(
        .auto, null, &field_names, &field_types, &field_attrs);
}

pub const FindError = error {
    NoSuchFlag,
    TypeMismatch,
    FlagNotSwitch,
    FlagNotArg,
};
