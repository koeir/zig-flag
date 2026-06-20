```zig
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.Type.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    const opts: Flags = result.flags;
    // arg list that has flags removed;
    // which includes values that were taken in by input type flags
    const args: []const [:0]const u8 = result.argv;

    if (opts.force) ...

    const recursive: bool = opts.recursive;
    const path: ?[:0]const u8 = opts.path;

    if (!recursive) ...
    std.debug.print("{s}\n", .{ path orelse "nowhere" });

    if (opts.files) |files| {
        for (files) |file| ...
    }
}
```
