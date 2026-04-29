```zig
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    const parsed = result.flags;

    if (parsed.force) // whatever

    const recursive: bool = parsed.recursive;
    const files: ?[][:0]const u8 = parsed.files;

    if (!recursive) //whatever

    for (files orelse &.{}) |file| {
        // whatever
    }
    ...
}
```
