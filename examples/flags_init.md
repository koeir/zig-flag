```zig
const zigflag = @import("zigflag");

const Init = zigflag.Type.Init;
const SwitchFlag = Init.SwitchFlag;     // bool (default flag type)
const InputFlag = Init.InputFlag;       // ?[:0]const u8
const InputFlag = Init.InputFlagMany;   // ?[][:0]const u8

const Flags = zigflag.Type.Flags;

// Initialize flags and their default values
// name doesn't really matter
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
            // value is a SwitchFlag by default
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
