# flagparse
A simple flag parser for Zig.

- No heap allocation
- Formatted printing
- Simple interface
- Returns argv list without flags

## Usage
1. Declare a list of flags with the built-in structs
``` zig
const initflags: flagparse.Type.Flags = .{
    .list = &[_] flagparse.Type.Flag 
    {
        .{
            .name = "recursive",
            .long = "recursive",
            .short = 'r',
            .value = .{ .Switch = false },
            .desc = "Recurse into directories",
        },

        .{
            .name = "force",
            .long = "force",
            .short = 'f',
            .value = .{ .Switch = false },
            .desc = "Skip confirmation prompts",
        },
        .{
            .name = "file",
            .long = "path",
            .short = 'p',
            .value = .{ .Argumentative = [_:0]u8{0} ** 1024 },
            .desc = "Path to file",
        },
    },
    
};

```

2. Initialize posix argument iterator and buffers
``` zig
const std = @import("std");
const flagparse = @import("flagparse");

pub fn main() !void {
    ...
    var args: std.process.ArgIteratorPosix = .init();

    var flagarr: [initflags.list.len]flagparse.Type.Flag = undefined;
    var argbuf: [20][:0]const u8 = undefined;
    ...

```

3. Parse
``` zig
const std = @import("std");
const flagparse = @import("flagparse");

pub fn main() !void {
    ...
    var args: std.process.ArgIteratorPosix = .init();

    // buffers; must remain in scope for flags and argv
    var flagarr: [initflags.list.len]flagparse.Type.Flag = undefined;
    var argbuf: [20][:0]const u8 = undefined;

    const result = try flagparse.parse(&args, argbuf[0..], initflags, &flagarr, .{})

    // retrieve values from tuple
    const flags = result.flags;
    const argv = result.argv;
    ...

```

4. Use
```zig
    ...
    const recursive: bool = try flags.get_value("recursive", bool);
    const file = try flags.get_value("file", [1024:0]u8);
    ...
```
