const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
	.name = "zig-opencl-test", 
	.root_source_file=.{.path="src/main.zig"},
	.target = target,
        .optimize = mode,
	});
    exe.addIncludePath(.{
	.path="./opencl-headers"
    });
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("OpenCL");
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
