const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const bmode = b.standardReleaseOptions();

    const do_strip = b.option(bool, "strip", "strip output; on for release-small") orelse (bmode == .ReleaseSmall);

    const exe = b.addExecutable("zdoc", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(bmode);
    exe.strip = do_strip;
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "run the executable");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(bmode);
    const test_step = b.step("test", "run tests");
    test_step.dependOn(&exe_tests.step);
}
