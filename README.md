# zig-flag

A simple flag parser for Zig programs. 
<br><br>
API documentation can be found [here](https://koeir.github.io) or made with [zig build docs](https://zig.guide/build-system/generating-documentation). If fetching from master, it is recommended do use `zig build docs` as the GitHub pages might not be updated.

## Features

- [Customizable formatted printing](README.md#printing-format)
- [Simple interface](README.md#usage)
- [Returns argv list without flags](README.md#usage)


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

    const exe = b.addExecutable(.{...});
    exe.root_module.addImport("zigflag", zigflag.module("zigflag"));
```

2. [Initialize flags](https://github.com/koeir/zigflag/blob/master/examples/flags_init.md)
```zig
pub const defaults: zigflag.Type.ComptimeFlags = .{
    .list = &.
    {
        .{
            .name = "recursive",
            .tag = "Switches",
            .long = "recursive",
            .short = 'r',
        //  .value = .init(.Switch),    // boolean; is the default, specifying this value is unnecessary
            .desc = "Recurse into directories",
        },
        .{
            .name = "path",
            .tag = "Input",
            .long = "path",
            .short = 'p',
            .value = .init(.Input), // or .initInput(.Single); ?[:0]const u8
            .desc = "Path to somewhere",
        },
        .{
            .name = "files",
            .tag = "Input",
            .long = "files",
            .short = 'f',
            .value = .initInput(.Many), // ?[][]const u8
            .desc = "Path to files",
        },
    }
};
```

3. [Parse flags](https://github.com/koeir/zigflag/blob/master/examples/parsing.md)
```zig
pub fn main(init: std.process.Init) !void {
    ...
    const parse = try zigflag.parse(init.gpa, min.args, defaults, .{});
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
    ...
```
The flags are stored in a struct in which the fields are names of the flags. Each field will have their corresponding values (`Switch`/`bool`, `Input.Single`/`?[:0]const u8`, `Input.Many`/`?[]const []const u8`). The struct also holds the inner arrays, and necessary components for deinit. `gpa` is used here, but it might be more convenient to use arena allocators.

4. [Use](https://github.com/koeir/zigflag/blob/master/examples/retrieving_values.md)
```zig
...
const Flags = zigflag.Type.StructFlags(defaults);

pub fn main(init: std.process.Init) !void {
    ...
    const opts: Flags = result.flags;
    // arg list that has flags removed;
    // which includes values that were taken in by input type flags
    const args: []const [:0]const u8 = result.argv;

    if (opts.force) ...

    const recursive: bool = opts.recursive;
    const path: ?[:0]const u8 = opts.path;

    if (!recursive) ...
    std.debug.print("{s}\n", .{ path orelse "nowhere" });

    if (opts.files) |files| {
        for (files) |file| ...
    }
    ...
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
  Switches:
     -r, --recursive.............. Recurse into directories
     -[n|f], --[no-]force......... Skip confirmation prompts

  Input:
     -p <file>, --path <file>..... Path to file
```

See [example.zig](examples/zig/example.zig) for more information.

## Errors

```zig
pub const ParseErrors = error {
    NoArgs,             // argc < 2
    NoSuchFlag,         // unrecognized flag in arg list
    FlagNotSwitch,      // non-switch/non-bool Flag treated as a switch/bool
    FlagNotArg,         // non-input type flag treated as an input type
    DuplicateFlag,      // flag appears twice in arg list; can be ignored with config
    MissingInput,       // no argument given to input type flag
    TypeMismatch,       // a more general FlagNotSwitch/FlagNotArg
}
```
