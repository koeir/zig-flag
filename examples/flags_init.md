```zig
const flagparse = @import("./src/root.zig");

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
