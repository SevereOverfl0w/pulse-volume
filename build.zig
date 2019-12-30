const std = @import("std");
const builtin = @import("builtin");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("pulse-vol", "pulse-vol.zig");
    exe.setBuildMode(builtin.Mode.ReleaseFast);
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("pulse");
    exe.setOutputDir(".");

    b.default_step.dependOn(&exe.step);
}
