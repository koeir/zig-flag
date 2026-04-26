const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flagparse = b.addModule("flagparse", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "flagparse",
        .root_module = flagparse,
        .linkage = .static,
    });

    b.installArtifact(lib);
}
