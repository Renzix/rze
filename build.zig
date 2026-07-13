const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("rze", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "rze",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .link_libc = true,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "rze", .module = mod },
            },
        }),
    });

    exe.root_module.linkSystemLibrary("SDL3", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const vm_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rzvm/vm.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_vm_tests = b.addRunArtifact(vm_tests);

    const test_step = b.step("testvm", "Run VM unit tests");
    test_step.dependOn(&run_vm_tests.step);

    const rzx_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/rzx/parser.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const run_rzx_tests = b.addRunArtifact(rzx_tests);

    const rzx_test_step = b.step("testrzx", "Run rzx parser unit tests");
    rzx_test_step.dependOn(&run_rzx_tests.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
