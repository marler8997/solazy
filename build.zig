const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const solazy = b.addModule("solazy", .{
        .root_source_file = b.path("src/solazy.zig"),
    });

    const test_so = b.addLibrary(.{
        .name = "test",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/testso.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // test_so.use_llvm = true;
    const install_test_so = b.addInstallArtifact(test_so, .{});
    b.step("install-test-so", "").dependOn(&install_test_so.step);

    const test_step = b.step("test", "");

    inline for (&.{ false, true }) |lazy| {
        const suffix: []const u8 = if (lazy) "-lazy" else "-greedy";
        const options = b.addOptions();
        options.addOption(bool, "lazy", lazy);
        const exe = b.addExecutable(.{
            .name = "test" ++ suffix,
            .root_module = b.createModule(.{
                .root_source_file = b.path("test/test.zig"),
                .target = target,
                .optimize = optimize,
                // .imports = &.{
                //     .{ .name = "solazy", .module = solazy },
                // },
                // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                // without this zig doesn't add PT_INTERP so our function
                // pointers are null and calling them causes segfaults
                .link_libc = !lazy,
            }),
        });
        exe.root_module.addOptions("build_options", options);
        if (lazy) {
            exe.root_module.addImport("solazy", solazy);
        }
        exe.linkLibrary(test_so);
        // exe.use_llvm = true;

        const install = b.addInstallArtifact(exe, .{});
        b.step("install-test" ++ suffix, "").dependOn(&install.step);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(&install.step);
        run.step.dependOn(&install_test_so.step);
        b.step("test" ++ suffix, "").dependOn(&run.step);
        test_step.dependOn(&run.step);
    }

    // const xcb = b.createModule(.{
    //     .root_source_file = b.path("xcb/xcb.zig"),
    // });

    // const examples = [_][]const u8{"xcb"};
    // for (examples) |example| {
    //     const exe = b.addExecutable(.{
    //         .name = example,
    //         .root_module = b.createModule(.{
    //             .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example})),
    //             .target = target,
    //             .optimize = optimize,
    //             .imports = &.{
    //                 .{ .name = "solazy", .module = solazy },
    //                 .{ .name = "xcb", .module = xcb },
    //             },
    //             // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    //             .link_libc = true,
    //         }),
    //     });
    //     if (std.mem.eql(u8, example, "xcb")) {
    //         exe.root_module.addImport("xcb", xcb);
    //         // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    //         exe.linkSystemLibrary("xcb");
    //     }

    //     const install = b.addInstallArtifact(exe, .{});
    //     b.step(b.fmt("install-{s}", .{example}), "").dependOn(&install.step);

    //     const run = b.addRunArtifact(exe);
    //     run.step.dependOn(&install.step);
    //     b.step(example, "").dependOn(&run.step);
    // }
}
