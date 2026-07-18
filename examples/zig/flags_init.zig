const zigflag = @import("./src/root.zig");

// Initialize flags and their default values
// name doesn't really matter as long as the
// members are all of type Flag
pub const options: zigflag.Type.InitFlags = .{
    .list = &.{
        // Sets name to either long or short, prioritizing long
        .init(.{ .short = 'r', .long = "recursive"}),
        .{
            .name = "force",
            .tag = "Switches",
            .short = 'f', .long = "force",
            .vanity = "-[n|f], --[no-]force",   // "vanity" overrides how it is printed
            .desc = "Skip confirmation prompts",
        },
        .{  // By default, "tag" is set to Options
            // setting a tag to null keeps it from being printed
            .name = "no-force",
            .tag = null,
            .short = 'n', .long = "no-force",
            .desc = "Do not skip confirmation prompts",
        },
        // Arguments will accept the next argv
        // e.g. -prf noob
        // "noob" will be accepted as the file
        .{
            .name = "files",
            .tag = "Input",
            .short = 'F', .long = "files",
            .value = .initInput(.Many),
            .desc = "Path to files",
        },
        .{
            .name = "path",
            .tag = "Input",
            .short = 'p', .long = "path",
            .value = .init(.Input), // or .initInput(.Single)
            .desc = "Path to somewhere",
        },
    }
};
