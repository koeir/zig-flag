const std = @import("std");
pub fn build(b: *std.Build) void {
    const flagparse = b.addModule("flagparse", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const lib = b.addLibrary(.{
        .name = "flagparse",
        .root_module = flagparse,
        .linkage = .static,
    });

    b.installArtifact(lib);
}
