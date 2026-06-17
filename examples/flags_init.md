```zig
const zigflag = @import("zigflag");
const Flags = zigflag.Type.Flags;
const Init = zigflag.Type.Init;

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type Flag
pub const defaults: Flags = .{
    .list = &.
    {
        .{
            .name = "recursive",
            .tag = "Switches",
            .long = "recursive",
            .short = 'r',
            .desc = "Recurse into directories",
        },
        .{
            .name = "force",
            .tag = "Switches",
            .long = "force",
            .short = 'f',
            .vanity = "-[n|f], --[no-]force",
            .desc = "Skip confirmation prompts",
        },
        .{  // by default, untagged flags will not be printed
            .name = "no-force",
            .long = "no-force",
            .short = 'n',
            .desc = "Do not skip confirmation prompts",
        },
        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "files",
            .tag = "Input",
            .long = "files",
            .short = 'F',
            .value = Init.InputFlagMany,
            .desc = "Path to files",
        },
        .{
            .name = "path",
            .tag = "Input",
            .long = "path",
            .short = 'p',
            .value = Init.InputFlag,
            .desc = "Path to somewhere",
        },
    }
};
```
