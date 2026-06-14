```zig
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    // Make config
    const parsecfg: zigflag.ParseConfig = .{
        .allowDashInput = true,
        .allowDups = true,
        .verbose = true,
        .writer = stderr,
        .prefix = "my-program: "
    };
    
    // points to erred flag
    var errptr: ?[]const u8 = null;
    defer if (errptr) |arg| init.gpa.free(arg); // parse allocates memory to errptr
    const result = zigflag.parse(init.gpa, init.minimal.args, defaults, &errptr, parsecfg)
    catch {
        try stderr.writeAll("\n");
        try stderr.writeAll("Usage: program [OPTIONS] <files>\n\n");
        try defaults.usage(stderr, .{ .tagStyle = .underline });
        return;
    }; defer result.deinit();

    // retrieving values
    const flags: Flags = result.flags;
    const argv: ?[][:0]const u8 = result.argv;
    ...
}
```
