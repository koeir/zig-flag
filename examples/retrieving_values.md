```zig
    const flags = result.flags;
    std.debug.print("recursive: {}\n", .{flags.recursive});
    std.debug.print("force: {}\n", .{flags.force});

    if (flags.files) |files| {
        std.debug.print("files:\n", .{});
        for (files) |file| {
            std.debug.print("{s} ", .{file});
        } std.debug.print("\n", .{});
    }

    if (result.argv) |args| {
        std.debug.print("flagless args:\n", .{});
        for (args) |arg| {
            std.debug.print("{s} ", .{arg});
        } std.debug.print("\n", .{});
    }
```
