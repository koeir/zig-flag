# Formatting
See [../src/Type.zig](../src/Type.zig)

```zig

// Formatted printing
try stdout.writeAll("Toggled flags:\n");
for (flags.list) |f| {
    if (!f.isDefault()) try stdout.print("{f}\n", .{ f } );
}

// Can be customized with the `Flag.fmt` declaration.
zigflag.Type.Flag.fmt = .{
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

## Structs
```zig
pub const Flag = struct {
...
    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    pub const Format = struct {
        fillerStyle: u8 = ' ',
        greyOutFiller: bool = false,
        greyOutDesc: bool = false,
        columns: enum {
            one, two
        } = .two,
        padding: struct {
            left: usize = 1,
            desc_left: usize = 1, // useless for columns.two; applied on top of .left
            center: usize = 30, //useless for columns.one
        } = .{},
    };

    // Customize this instance
    pub var fmt = Format{};
...
}
```
```zig
pub const Flags = struct {
...
    pub const UsageConfig = struct {
        padding_left: usize = 0,
        printUntagged: bool = false,
        untaggedFirst: bool = true,
        tagStyle: enum {
            brackets, colon, underline
        } = .colon
    };
...
}
```
