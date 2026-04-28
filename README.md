# zig-flag

A simple flag parser for Zig programs. 
<br><br>
API documentation can be found [here](https://koeir.github.io) or made with [zig build docs](https://zig.guide/build-system/generating-documentation). If fetching from master, it is recommended do use `zig build docs` as the GitHub pages might not be updated.

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
// Specific tag
zig fetch --save https://github.com/koeir/zigflag/archive/refs/tags/v0.x.x.tar.gz

// Or master branch
zig fetch --save git+https://github.com/koeir/zigflag
```

```zig
    // build.zig
    const zigflag = b.dependency("zigflag", .{
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

    exe.root_module.addImport("zigflag", zigflag.module("zigflag"));
    b.installArtifact(exe);
```

2. [Initialize flags](https://github.com/koeir/zigflag/blob/master/examples/flags_init.md)
```zig
const zigflag = @import("zigflag");

const SwitchFlag = zigflag.Type.SwitchFlag;
const InputFlag = zigflag.Type.InputFlag;

const Flags = zigflag.Type.Flags;
const Flag = zigflag.Type.Flag;

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type zigflag
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

3. [Parse flags](https://github.com/koeir/zigflag/blob/master/examples/parsing.md)
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

4. [Use](https://github.com/koeir/zigflag/blob/master/examples/retrieving_values.md)
```zig
const defaults = @import("./init_flags.zig").defaults;
const Flags = zigflag.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
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
    ...
}
```

5. [Optionally customize](examples/formatting.md)
```zig
    // warning:
    //
    // center padding is calculated by
    // value - n of chars in "-<s>, --<long>"
    // so make sure the padding is enough
    zigflag.Type.Flag.fmt = .{
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
