```zig
const std = @import("std");
const zigflag = @import("zigflag");
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.Type.FlagsLUT(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    // Make config
    const parsecfg: zigflag.ParseConfig = .{
        .allowDashInput = true,
        .exitFirstErr = false,
        .allowDups = true,
        .delimiters = ",:"
    };
    
    const parse = try zigflag.parse(init.gpa, min.args, defaults, parsecfg);
    defer parse.deinit(init.gpa);

    // error checking and retrieving values
    const result = switch (parse) {
        .Ok  => | ok | ok,
        .Err => |errs| {
            for (errs.items) |err| {
                std.debug.print("{s}: {s}\n", .{
                    err.cause, @errorName(err.err)
                });
            } return;
        },
    };

    const flags: Flags = result.flags;
    const positionals: [][:0]const u8 = result.pos;
    ...
}
```
