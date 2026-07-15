```zig
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.Type.FlagsLUT(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    const opts: Flags = result.flags;
    // positionals / list of arguments without flags
    const positionals: []const [:0]const u8 = result.pos;

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
