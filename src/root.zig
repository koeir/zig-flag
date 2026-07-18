const std = @import("std");
const helpers = @import("helpers.zig");
pub const Type = @import("Type.zig");

const mem = std.mem;

pub const flagfmt = helpers.flagfmt;
pub const parse = Parse.parse;

pub const Parse = struct {
    // Memory returned must be freed
    pub fn parse(
        allocator: mem.Allocator,
        args: std.process.Args,
        comptime defaults: Type.InitFlags,
        cfg: ParseConfig,
    ) !ParsedResult(defaults) {
        var iter = args.iterate();

        // Initialize the parsed flags
        var parsed_flags = try allocator.create(Type.RuntimeFlags);
        parsed_flags.* = try .init(allocator, defaults.list);
        errdefer {
            parsed_flags.deinit(allocator);
            allocator.destroy(parsed_flags);
        }

        var positionals = try allocator.create(std.ArrayList([:0]const u8));
        positionals.* = try .initCapacity(allocator, args.vector.len);
        errdefer {
            // deinit and destroy pointer
            positionals.deinit(allocator);
            allocator.destroy(positionals);
        }

        var errs = try allocator.create(std.ArrayList(ParseErrorPackage));
        errs.* = try .initCapacity(allocator, args.vector.len);
        errdefer {
            // deinit and destroy pointer
            errs.deinit(allocator);
            allocator.destroy(errs);
        }

        defer if (errs.items.len > 0) {
            // free items on error
            // before returning to the previous stack frame
            parsed_flags.deinit(allocator);
            allocator.destroy(parsed_flags);
            positionals.deinit(allocator);
            allocator.destroy(positionals);
        } else {
            // free errors array if successful
            errs.deinit(allocator);
            allocator.destroy(errs);
        };

        while (iter.next()) |arg| {
            const fmt: Type.Flag.FlagFmt = helpers.flagfmt(arg) orelse {
                // If it isn't a flag, add it to positionals and continue
                //
                // note that input flags take the next arg,
                // which would be skipped by the iterator
                try positionals.append(allocator, arg);
                continue;
            };

            // Slice out dashes
            switch (fmt) {
                .Long   => helpers.parseFlag(allocator, arg[2..], fmt, parsed_flags.*, &iter, cfg)
                catch |err| {
                    try errs.append(allocator, .{
                        .cause = try allocator.dupe(u8, arg),
                        .err = err
                    });
                },
                // Iterate through each char
                .Short  => for (arg[1..]) |c| {
                    helpers.parseFlag(allocator, &[_]u8 {c}, fmt, parsed_flags.*, &iter, cfg)
                    catch |err| {
                        const cause = try mem.concat(allocator, u8, &.{
                            "-", &.{c}
                        });

                        try errs.append(allocator, .{
                            .cause = cause,
                            .err = err,
                        });
                    };
                },
            }

            if (errs.items.len > 0 and cfg.exitFirstErr)
                return .{ .Err = errs };
        }

        // Return errs
        if (errs.items.len > 0) return .{ .Err = errs };
        if (positionals.items.len == 1 and cfg.errOnNoArgs) {
            try errs.append(allocator, .{
                .err = ParseError.NoArgs
            }); return .{ .Err = errs };
        }

        // shrink positionals it because it's guaranteed to be <= args
        if (positionals.items.len < args.vector.len)
            try positionals.resize(allocator, positionals.items.len);

        // Return successful
        return .init(positionals, parsed_flags);
    }

    /// Setting allowDups to true allows InputSingles to be overwritten if its flag is repeated
    pub const ParseConfig = struct {
        allowDups: bool = false,
        allowDashInput: bool = true,
        errOnNoArgs: bool = false,
        exitFirstErr: bool = true,
        delimiters: []const u8 = ",",
    };

    pub const ParseErrorPackage = struct {
        err: anyerror,
        cause: ?[]const u8 = null,
    };

    pub const ParseError = error {
        NoArgs,
        NoSuchFlag,
        FlagNotSwitch,      // non-switch/non-bool Type.Flag treated as a switch/bool
        FlagNotInput,       // non-input flag treated as an input
        DuplicateFlag,
        MissingInput,       // no argument given to input flag
        TypeMismatch,       // failure to retrieve value, type given does not match value
    };

    /// Constructs and populates results for flagless arg list, flags, allocator, etc.
    pub fn ParsedResult(comptime defaults: Type.InitFlags) type {
        return union(enum) {
            Err: *std.ArrayList(ParseErrorPackage),
            Ok: struct {
                pos: []const [:0]const u8,
                flags: FlagsLUT(defaults),
                // Shouldn't be accessed manually. Should only be accessed by init and deinit.
                inner: struct {
                    flags: *Type.RuntimeFlags,
                    pos: *std.ArrayList([:0]const u8),
                },
            },

            pub fn init(
                pos: *std.ArrayList([:0]const u8),
                flags: *Type.RuntimeFlags,
            ) @This() {
                const struct_flags = helpers.populateStruct(FlagsLUT(defaults), flags.*);

                return .{
                    .Ok = .{
                        .pos = pos.items,
                        .flags = struct_flags,
                        .inner = .{
                            .pos = pos,
                            .flags = flags
                        }
                    }
                };
            }

            pub fn deinit(self: *const @This(), allocator: mem.Allocator) void {
                switch (self.*) {
                    .Ok => |*results| {
                        results.inner.flags.deinit(allocator);
                        results.inner.pos.deinit(allocator);
                        allocator.destroy(results.inner.pos);
                        allocator.destroy(results.inner.flags);
                    },
                    .Err => |errs| {
                        for (errs.items) |err| {
                            // Memory is allocated in root, duping and concatting strings.
                            if (err.cause) |cause| allocator.free(cause);
                        }

                        errs.deinit(allocator);
                        allocator.destroy(errs);
                    }
                }
            }
        }; // lol
    }

    /// Initializes a struct/look-up table for holding values of parsed flags/arguments.
    /// Essentially simplifies the defaults flag array in comptime to key:value pairs
    pub fn FlagsLUT(comptime defaults: Type.InitFlags) type {
        // Checks for duplicate names, longs, shorts, and if a flag is missing short/long
        inline for (defaults.list, 0..) |flag1, i| {
            if (flag1.short == null and flag1.long == null)
                @compileError("option has no flag: " ++ flag1.name);

            inline for (defaults.list, 0..) |flag2, j| {
                if (i == j) continue;

                if (mem.eql(u8, flag1.name, flag2.name))
                    @compileError("option has duplicate(s) name: " ++ flag1.name);

                if (flag1.long) |long1| {
                    if (flag2.long) |long2| {
                        if (mem.eql(u8, long1, long2))
                            @compileError("option has duplicate(s) long flag: " ++ flag1.name);
                    }
                }

                if (flag1.short) |short1| {
                    if (flag2.short) |short2| {
                        if (short1 == short2)
                            @compileError("option has duplicate(s) short flag: " ++ flag1.name);
                    }
                }
            }
        }

        comptime var field_names: [defaults.list.len][]const u8 = undefined;
        comptime var field_types: [defaults.list.len]type = undefined;
        comptime var field_attrs: [defaults.list.len]std.builtin.Type.StructField.Attributes = undefined;

        inline for (defaults.list, 0..) |value, i| {
            const T = switch (value.value) {
                .Input => |in| switch (in) {
                        .Single => ?[:0]const u8,
                        .Many   => ?[][]const u8
                },
                .Switch => bool,
            };

            field_names[i] = value.name;
            field_types[i] = T;
            field_attrs[i] = .{
                .@"align" = @alignOf(T),
            };
        }

        return @Struct(
            .auto
            ,null
            ,&field_names
            ,&field_types
            ,&field_attrs
        );
    }
};

/// Returns error messages for select flag errors.
pub fn errorMessage(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.NoArgs         => "Missing arguments",
        error.NoSuchFlag     => "No such flag",
        error.DuplicateFlag  => "Duplicate flag",
        error.MissingInput   => "No argument supplied",
        else                 => null,
    };
}
