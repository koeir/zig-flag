```zig
    const defaults = @import("./init_flags.zig").defaults;
    const Flags = zigflag.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    // Make config
    const parsecfg: zigflag.Type.ParseConfig = .{
        .allowDashInput = true,
        .allowDups = true,
        .verbose = true,
        .writer = stderr,
        .prefix = "my-program: "
    };
    
    // points to erred flag
    var errptr: ?[]const u8 = null;
    // actual parse, returns a tuple of Flags and resulting args
    const result = try zigflag.parse(init.gpa, min.args, defaults, &errptr, parsecfg);
    defer result.deinit();

    // retrieving values
    const flags: Flags = result.flags;
    const argv: ?[][:0]const u8 = result.argv;
    ...
}
```
