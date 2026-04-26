```zig
const default_flags = @import("./flags_init.zig").defaults;

const gpa = init.gpa;
var errptr = ?[]const u8 = null;

const results = zigflag.parse(
    gpa, min.args, defaults_flags, &errptr,
    // Config options
    .{ .allowDups = false, .verbose = true, .writer = stderr, .prefix = "my-program: ", .errOnNoArgs = true, }, ) 
catch |err| {
    if (err != zigflag.Type.FlagError.ArgNoArg) return;

    const arg: []const u8 = errptr orelse return;
    const flagtmp = defaults_flags.getWithFlag(arg) orelse return;

    // "Usage" output when parse fails
    try stderr.writeAll("\nUsage:\n");
    try stderr.print("{f}\n", .{ flagtmp.* });

    return;
}; results.deinit(allocator);

// Retrieving values
_ = results.flags;
_ = results.argv;
```
