# Formatting
See [../src/Type.zig](../src/Type.zig)

```zig

// Formatted printing
try stdout.writeAll("Toggled flags:\n");
for (flags.list) |f| {
    if (!f.isDefault()) try stdout.print("{f}\n", .{ f } );
}

// Can be customized with the `Flag.fmt` declaration.
flagparse.Type.Flag.fmt = .{
    .columns = .one,
    .padding = .{
        .left = 5,
    },
    .fillerStyle = ' ',  // default
    .greyOutDesc = true,
};

// The `Flags` type also has a method `.usage()` that prints all flags
// with their respective tags; can also be customized with its
// `Flags.UsageFormat` struct
try stdout.writeAll("\nUsage:\n\n");
try default_flags.usage(stdout, .{ .padding_left = 2, .tagStyle = .underline });

```

```zsh
Toggled flags:
 -r, --recursive               Recurse into directories
 -[n|f], --[no-]force          Skip confirmation prompts
 -p <file>, --path <file>      Path to file

Usage:

  Switches
     -r, --recursive
    Recurse into directories


     -[n|f], --[no-]force
    Skip confirmation prompts


  Input
    -p , --path 
    Path to file

```
