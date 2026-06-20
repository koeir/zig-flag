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
        comptime defaults: Type.Flags,
        cfg: ParseConfig,
    ) !ParsedResult(defaults) {
        var iter = args.iterate();

        // Initialize the parsed flags
        const out_flags = try allocator.dupe(Type.Flag, defaults.list);
        errdefer allocator.free(out_flags);

        var out_args = try allocator.create(std.ArrayList([:0]const u8));
        out_args.* = try .initCapacity(allocator, args.vector.len);
        errdefer {
            // deinit and destroy pointer
            out_args.deinit(allocator);
            allocator.destroy(out_args);
        }

        var errs = try allocator.create(std.ArrayList(ParseErrorPackage));
        errs.* = try .initCapacity(allocator, args.vector.len);
        errdefer {
            // deinit and destroy pointer
            errs.deinit(allocator);
            allocator.destroy(errs);
        }

        defer if (errs.items.len > 0) {
            // If returning error, free dis
            allocator.free(out_flags);
            out_args.deinit(allocator);
            allocator.destroy(out_args);
        } else {
            // else free errors
            errs.deinit(allocator);
            allocator.destroy(errs);
        };

        while (iter.next()) |arg| {
            const fmt: Type.Flag.FlagFmt = helpers.flagfmt(arg) orelse {
                // If it isn't a flag, add it to out_args and continue
                //
                // note that input flags take the next arg,
                // which would be skipped by the iterator
                try out_args.append(allocator, arg);
                continue;
            };

            // Slice out dashes
            switch (fmt) {
                .Long   => helpers.parse_flag(allocator, arg[2..], fmt, out_flags, &iter, cfg)
                catch |err| {
                    try errs.append(allocator, .{
                        .cause = try allocator.dupe(u8, arg),
                        .err = err
                    });
                },
                // Iterate through each char
                .Short  => for (arg[1..]) |c| {
                    helpers.parse_flag(allocator, &[_]u8 {c}, fmt, out_flags, &iter, cfg)
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
        if (out_args.items.len == 1 and cfg.errOnNoArgs) return error.NoArgs;

        // shrink out_args it because it's guaranteed to be <= args
        if (out_args.items.len < args.vector.len)
            try out_args.resize(allocator, out_args.items.len);

        // Return successful
        return .init(allocator, out_args, out_flags);
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
        cause: []const u8,
    };

    pub const ParseError = error {
        NoArgs,
        NoSuchFlag,
        FlagNotSwitch,      // non-switch/non-bool Type.Flag treated as a switch/bool
        FlagNotArg,         // non-argumentative flag treated as an argumentative
        DuplicateFlag,
        ArgNoArg,           // no argument given to argumentative flag
        TypeMismatch,       // failure to retrieve value, type given does not match value
    };

    pub const Result = enum {
        Ok, Err
    };

    /// Constructs and populates results for flagless arg list, flags, allocator, etc.
    pub fn ParsedResult(comptime defaults: Type.Flags) type {
        return union(Result) {
            const Self = @This();

            Ok: struct {
                argv: [][:0]const u8,
                flags: StructFlags(defaults),
                inner: struct {
                    flags: []Type.Flag,
                    argv: *std.ArrayList([:0]const u8),
                },
            },

            Err: *std.ArrayList(ParseErrorPackage),

            pub fn init(
                allocator: mem.Allocator,
                argv: *std.ArrayList([:0]const u8),
                flags_array: []Type.Flag,    // Memory is allocated in root.parse(). 
                                        // It is allocated with a known array len, taken from the number of flags in initialized defaults.
            ) !Self {
                // Using hashmap for cleaner code in populateStruct
                var parsed: std.StringHashMap(Type.Flag) = .init(allocator);
                defer parsed.deinit();

                for (flags_array) |flag| {
                    try parsed.put(flag.name, flag);
                }

                const struct_flags = try helpers.populateStruct(StructFlags(defaults), parsed);

                return .{
                    .Ok = .{
                        .argv = argv.items,
                        .flags = struct_flags,
                        .inner = .{
                            .argv = argv,
                            .flags = flags_array
                        }
                    }
                };
            }

            pub fn deinit(self: *const @This(), allocator: mem.Allocator) void {
                switch (self.*) {
                    .Ok => |*results| {
                        for (results.inner.flags) |*flag| {
                            if (flag.value != .Input 
                            or flag.value.Input == .Single) 
                                continue;
                            // Only many is deinit/freed because Single uses os argv and does not allocate memory
                            if (flag.value.Input.Many) |*input| input.deinit(allocator);
                        } allocator.free(results.inner.flags);

                        results.inner.argv.deinit(allocator);
                        allocator.destroy(results.inner.argv);
                    },
                    .Err => |errs| {
                        for (errs.items) |err| {
                            // Memory is allocated in root, duping and concatting strings.
                            allocator.free(err.cause);
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
    ///
    /// Is in public scope for aliasing Type.Flags type in main or whatever
    pub fn StructFlags(comptime defaults: Type.Flags) type {
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
            .auto, null, &field_names, &field_types, &field_attrs);
    }
};

/// Returns error messages for select flag errors.
pub fn error_message(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.NoArgs         => "Missing arguments",
        error.NoSuchFlag     => "No such flag",
        error.DuplicateFlag  => "Duplicate flag",
        error.ArgNoArg       => "No argument supplied",
        else                 => null,
    };
}
