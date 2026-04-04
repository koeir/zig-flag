const std = @import("std");
const flag = @import("flagparse");

pub fn main() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var alloc_buffer: [1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&alloc_buffer);

    // parse requires       vvvvvvvvvvvv
    var args: std.process.ArgIteratorPosix = .init();

    // .init makes a mutable runtime version of the initialized Flags
    // Declarations are turned into fields
    //
    //          v COMPTIME STRUCT v                       v RUNTIME STRUCT v
    // _____________________________________       _________________________________
    // [ const Flags = struct {            ]       [   const Result = struct {     ]
    // [      pub const recursive = ...    ]  -->  [       .recursive = ...        ]
    // [___________________________________]       [_______________________________]
    const Result = comptime flag.init(Flags);

    // Make a mutable instance populated with the default values
    var mut_flags = Result{};
    _ = &mut_flags;

    // (WIP)
    // parse is a runtime function that actually changes
    // the values of the mutable
    var flags: Result = try flag.parse(&args, Flags, Result);
    _ = &flags;

    // Long hands and short hands
    try stdout.print("Longhand:  --{s}\n", .{ flags.recursive.long.? });
    try stdout.print("Shorthand: -{c}\n", .{ flags.recursive.short.? });

    // Value
    try stdout.print("Recursion is: {}\n", .{ flags.recursive.value.Switch });

    // Mutate value
    try stdout.print("\nForce: {}\n", .{ flags.force.value });
    try flags.force.toggle();
    try stdout.print("Force: {}\n", .{ flags.force.value });

    // Set path
    const path: []const u8 = try flags.file.set_arg(fba.allocator(), "/path/to/file");
    defer fba.allocator().free(path);

    try stdout.print("Path: {s}\n", .{ flags.file.value.Argumentative });

    // Print all flags
    try stdout.writeAll("\nFlags:\n");
    inline for (@typeInfo(Flags).@"struct".decls) |decl| {
        try stdout.print("{f}\n", .{ @field(Flags, decl.name) });
    }
}

// Initialize flags and their default values
const Flags = struct {
    pub const recursive: flag.Flag = .{
        .long = "recursive",
        .short = 'r', 
        .value = .{ .Switch = false },
        .opt = true,
        .desc = "Recurse within directories",
    };

    pub const force: flag.Flag = .{
        .long = "force",
        .short = 'f',
        .value = .{ .Switch = false },
        .opt = true,
        .desc = "Skip confirmation prompts",
    };

    pub const file: flag.Flag = .{
        .long = "path",
        .short = 'p',
        .value = .{ .Argumentative = undefined },
        .opt = true,
        .desc = "Path to file",
    };
};
