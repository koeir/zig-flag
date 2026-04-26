```zig
// The `Flag` type has a `.format()` method that can be customized 
// with the `Flag.Format` struct
try stdout.writeAll("Toggled flags:\n");
for (flags.list) |f| {
    if (!f.isDefault()) try stdout.print("{f}\n", .{ f } );
}

// The `Flags` type also has a method `.usage()` that prints all flags
// with their respective types; can also be customized with its
// `Flags.UsageFormat` struct
try stdout.writeAll("\nUsage:\n");
try initflags.usage(stdout, .{});
```
