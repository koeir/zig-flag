# flagparse

A simple flag parser for Zig programs.

## Features

- Formatted printing
- Simple interface
- Returns argv list without flags

## Config Options

### Parse Config

- **allowDups**: Don't error when duplicate flags are set. _Default is false_.
- **verbose**: Print out error messages when errors occur. _Default is false_.
- **writer**: Required when using verbose option. Doesn't really do anything without it. _Default is null_.
- **prefix**: Print out a custom string for verbose messages. _Default is null_.
- **allowDashAsFirstCharInArgForArg**: I admit this needs a better name. It allows argumentative type flags (meaning flags that hold a string/arg) to hold strings that begin with "-". _Default is true_.
- **errOnNoArgs**: Outputs an error if there are no arguments except argv[0]. _Default is false_.
- **exitFirstErr**: Exit on first error found. _Default is true_.

### Usage Config

Config for `Type.Flags.usage()` method

- **padding_left**: Number of whitespaces before the tag. _Default is 0_
- **printUntagged**: Print untagged flags. _Default is false_.
- **untaggedFirst**: Print untagged flags first. Prints last when false. _Default is true_.

## Usage

1. Fetch with zig and add as module in build.zig

```zsh
zig fetch --save https://github.com/koeir/flagparse/archive/refs/tags/v0.x.x.tar.gz
```

```zig
    // build.zig
    const flagparse = b.dependency("flagparse", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        })
    });

    exe.root_module.addImport("flagparse", flagparse.module("flagparse"));
    b.installArtifact(exe);
```

2. Declare a list of flags with the built-in structs

```zig
const initflags: flagparse.Type.Flags = .{
    .list = &[_] flagparse.Type.Flag
    {
        .{
            .name = "recursive",
            .tag = "Switches",
            .long = "recursive",        // long flags and short flags are maybe values;
            .short = 'r',               // if both are missing then they can't... be set
            .value = .{ .Switch = false },
            .desc = "Recurse into directories",
        },
        .{
            .name = "force",            // will not be printed because Type.UsageConfig.printUntagged is false by default
            .long = "force",
            .value = .{ .Switch = false },
            .desc = "Skip confirmation prompts",
        },
        .{
            .name = "noForce",
            .long = "no-force",
            .value = .{ .Switch = false },
            .desc = "Do not skip confirmation prompts",
        },
        .{
            .name = "force-vanity",     // 'vanity'; shows in usage(), but cannot be toggled
            .tag = "Switches",
            .long = "[no-]force",
            .isVanity = true,
            .value = .{ .Switch = false }, //value doesn't matter because it's vanity
            .desc = "Don't skip/skip confirmation prompts",
        },

        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "file",
            .tag = "Input",
            .long = "path",
            .short = 'p',
            .value = .{ .Argumentative = null },
            .desc = "Path to file",
        },
    }
};
```

3. Initialize args, allocators, and error pointer for handling

```zig
const std = @import("std");
const flagparse = @import("flagparse");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const min = init.minimal;

    var gpa = std.heap.DebugAllocator(.{}){};
    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
    defer arena.deinit();

    // points to last flag on error
    var errptr: ?[]const u8 = null;
    ...

```

4. Parse

```zig
const std = @import("std");
const flagparse = @import("flagparse");

pub fn main() !void {
    ...
    // returns a tuple of Flags and resulting args
    // resulting args is a maybe value
    const result = flagparse.parse(arena.allocator(), min.args, initflags, &errptr, .{}) catch |err| {
        const arg_error = errptr.?;
        // handle err
        return;
    };
    ...

```

5. Use

```zig
    ...
    // retrieve tuple values
    const flags = result.flags;
    const flagless_args = result.argv;

    const recursive: bool = try flags.value("recursive", flagparse.Type.Switch);
    const file: ?[:0]const u8 = try flags.value("file", flagparse.Type.Argumentative);

    if (recursive) // do stuff

    if (flagless_args) |args| {
        // do stuff
    }
    ...
```

## Printing Format

The Flags struct has a method `usage()` that prints all flags with their respective tags. Tags that appear first in the array of the init flags are printed first. Whether the flags without tags are printed first or last can be change with the config option `untaggedFirst: bool`.

```zsh
  Switches:
     -r, --recursive               Recurse into directories
         --[no-]force              Don\'t skip/skip confirmation prompts

  Input:
     -p <file>, --path <file>      Path to file
```

Individual flags`: Type.Flag` can also be printed with their `format()` method via `{f}` print format. The left-padding and the padding between the flags and their descriptions can be changed with the `.padding` variable in the `Type.Flag` struct.

```zig
// e.g.
// This affects the printing of `Type.Flags.usage()` too
flagparse.Type.Flag.padding = {
    .left = 1,
    .center = 20,
    .style = '.'    // change what is printed between the flags and descriptions
                    // default is whitespace (' ')
}
```

```zsh
 -r, --recursive.... Recurse into directories
```

## Errors

```zig
pub const FlagErrs = error {
    NoArgs,             // argc < 2
    NoSuchFlag,         // unrecognized flag in arg list
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-argumentative flag treated as an argumentative
    DuplicateFlag,      // flag appears twice in arg list; can be ignored with config
    ArgNoArg,           // no argument given to argumentative flag
    NoWriter,           // no writer given when verbose is true
    TypeMismatch,       // a more general FlagNotSwitch/FlagNotArg
}
```
