# flagparse

A simple flag parser for Zig programs. API documentation can be found at my [github pages site](https://koeir.github.io).

## Features

- [Customizable formatted printing](README.md#printing-format)
- [Simple interface](README.md#usage)
- [Returns argv list without flags](README.md#usage)

## Config Options

### Parse Config
See [Type.ParseConfig](src/Type.zig)
- **allowDups**: Don't error when duplicate flags are set. _Default is false_.
- **verbose**: Print out error messages when errors occur. _Default is false_.
- **writer**: Required when using verbose option. Doesn't really do anything without it. _Default is null_.
- **prefix**: Print out a custom string for verbose messages. _Default is null_.
- **allowDashInput**: Allow input type flags to hold strings that begin with "-". _Default is true_.
- **errOnNoArgs**: Outputs an error if there are no arguments except argv[0]. _Default is false_.
- **exitFirstErr**: Exit on first error found. _Default is true_.

### Print Formatting
See [examples/formatting.md](examples/formatting.md)

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

2. [Initialize flags](https://github.com/koeir/flagparse/blob/master/examples/flags_init.md)
```zig
const flagparse = @import("flagparse");

const SwitchFlag = flagparse.Type.SwitchFlag;
const InputFlag = flagparse.Type.InputFlag;

const Flags = flagparse.Type.Flags;
const Flag = flagparse.Type.Flag;

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type flagparse
pub const defaults: Flags = .{
    .list = &[_]Flag
    {
        .{
            .name = "recursive",
            .tag = "Switches",
            .long = "recursive",
            .short = 'r',
            .value = SwitchFlag,
            .desc = "Recurse into directories",
        },
        .{
            .name = "force",
            .tag = "Switches",
            .long = "force",
            .short = 'f',
            .vanity = "-[n|f], --[no-]force",
            .value = SwitchFlag,
            .desc = "Skip confirmation prompts",
        },
        .{  // by default, untagged flags will not be printed
            .name = "no-force",
            .long = "no-force",
            .short = 'n',
            .value = SwitchFlag,
            .desc = "Do not skip confirmation prompts",
        },
        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "file",
            .tag = "Input",
            .long = "path",
            .short = 'p',
            .value = InputFlag,
            .desc = "Path to file",
        },
    }
};
```

3. [Parse flags](https://github.com/koeir/flagparse/blob/master/examples/parsing.md)
```zig
const default_flags = @import("./flags_init.zig").defaults;

const arena = init.arena.allocator();
var errptr = ?[]const u8 = null;

const results = flagparse.parse(arena, min.args, defaults_flags, &errptr, .{ ... }, )
catch |err| {
    // handle errors
}; // results.deinit(allocator); if gpa, though results has to be var

// Retrieving values
const flags: flagparse.Type.Flags = results.flags;
const argv: ?std.ArrayList([:0]const u8) = results.argv;
```

4. [Use](https://github.com/koeir/flagparse/blob/master/examples/retrieving_values.md)
```zig
// Existance of flags are checked in comptime
_ = flags.compGet("recursive", default_flags); // returns a pointer to the flag
_ = flags.compGetValue(Switch, "recursive", default_flags); // Switch = bool;

// Will cause compilation errors
// _ = flags.compGetValue(Input, "recursive", default_flags);
// _ = flags.compGet("hey i dont exist", default_flags);

// non-comptime variants
const file: Input = try flags.getValue(Input, "file"); // Input = ?[:0]const u8;
if (file) |val| // do stuff

const force = flags.getWithFlag("force") orelse return;
const recursive = flags.getWithFlag(&[_]u8 { 'r' }) orelse return;

// also .get(...), .tryGet(...) and that returns a pointer to the flag itself
```

5. [Optionally customize](examples/formatting.md)
```zig
    // warning:
    //
    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    // so make sure the padding is enough
    flagparse.Type.Flag.fmt = .{
        .padding = .{
            .left = 5,
            .center = 30,
        },
        .greyOutFiller = true,
        .fillerStyle = '.',
    };

```

```zsh
Usage:

  Switches:
     -r, --recursive.............. Recurse into directories
     -[n|f], --[no-]force......... Skip confirmation prompts

  Input:
     -p <file>, --path <file>..... Path to file
```

## Errors

```zig
pub const FlagErrs = error {
    NoArgs,             // argc < 2
    NoSuchFlag,         // unrecognized flag in arg list
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-input type flag treated as an input type
    DuplicateFlag,      // flag appears twice in arg list; can be ignored with config
    ArgNoArg,           // no argument given to input type flag
    NoWriter,           // no writer given when verbose is true
    TypeMismatch,       // a more general FlagNotSwitch/FlagNotArg
}
```
