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

    const install_test_so = b.addInstallArtifact(test_so, .{});
    b.step("install-test-so", "").dependOn(&install_test_so.step);

    const test2_so = b.addLibrary(.{
        .name = "test2",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/test2so.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const install_test2_so = b.addInstallArtifact(test2_so, .{});
    b.step("install-test2-so", "").dependOn(&install_test2_so.step);

    const test_step = b.step("test", "");

    inline for (&.{ false, true }) |lazy| {
        const suffix: []const u8 = if (lazy) "-lazy" else "-greedy";
        const options = b.addOptions();
        options.addOption(bool, "lazy", lazy);
        if (lazy) {
            options.addOptionPath("testso", test_so.getEmittedBin());
            options.addOptionPath("test2so", test2_so.getEmittedBin());
        }
        const exe = b.addExecutable(.{
            .name = "test" ++ suffix,
            .root_module = b.createModule(.{
                .root_source_file = b.path("test/test.zig"),
                .target = target,
                .optimize = optimize,
                // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                // without this zig doesn't add PT_INTERP so our function
                // pointers are null and calling them causes segfaults
                .link_libc = !lazy,
            }),
        });
        exe.root_module.addOptions("build_options", options);
        if (lazy) {
            exe.root_module.addImport("solazy", solazy);
            switch (target.result.os.tag) {
                .windows => {},
                else => exe.linkSystemLibrary("dl"),
            }
        }
        exe.linkLibrary(test_so);
        exe.linkLibrary(test2_so);
        if (target.result.os.tag == .windows) {
            exe.addLibraryPath(test_so.getEmittedBinDirectory());
            exe.addLibraryPath(test2_so.getEmittedBinDirectory());
        }

        const install = b.addInstallArtifact(exe, .{});
        b.step("install-test" ++ suffix, "").dependOn(&install.step);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(&install.step);
        run.step.dependOn(&install_test_so.step);
        run.step.dependOn(&install_test2_so.step);
        run.expectExitCode(0);
        b.step("test" ++ suffix, "").dependOn(&run.step);
        test_step.dependOn(&run.step);
    }

    {
        const readme_step = b.step("test-readme", "Extract and test README.md examples");
        const blocks = comptime extractZigBlocks(@embedFile("README.md"));
        const wf = b.addWriteFiles();
        inline for (blocks, 0..) |block, i| {
            const exe = b.addExecutable(.{
                .name = std.fmt.comptimePrint("readme-example-{d}", .{i}),
                .root_module = b.createModule(.{
                    .root_source_file = wf.add(std.fmt.comptimePrint("readme_example_{d}.zig", .{i}), block),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            exe.root_module.addImport("solazy", solazy);
            switch (target.result.os.tag) {
                .windows => {},
                else => exe.linkSystemLibrary("dl"),
            }
            // Example with fallback (.func) are self-contained and can run.
            // Others (e.g. .panic with a nonexistent lib) only verify compilation.
            if (comptime std.mem.indexOf(u8, block, ".func") != null) {
                const run = b.addRunArtifact(exe);
                run.expectExitCode(0);
                readme_step.dependOn(&run.step);
            } else {
                readme_step.dependOn(&exe.step);
            }
        }
        test_step.dependOn(readme_step);
    }
}

/// Find "```zig" fenced blocks in markdown, handling both LF and CRLF.
/// Returns slices directly into `src` (must be a comptime constant like @embedFile).
fn countZigBlocks(comptime src: []const u8) usize {
    comptime {
        @setEvalBranchQuota(100_000);
        var count: usize = 0;
        var pos: usize = 0;
        while (pos < src.len) {
            pos = std.mem.indexOfPos(u8, src, pos, "```zig") orelse break;
            pos += "```zig".len;
            // Must be followed by a newline (skip optional \r)
            if (pos < src.len and src[pos] == '\r') pos += 1;
            if (pos < src.len and src[pos] == '\n') {
                count += 1;
                pos += 1;
            }
        }
        return count;
    }
}

fn extractZigBlocks(comptime src: []const u8) [countZigBlocks(src)][]const u8 {
    comptime {
        @setEvalBranchQuota(100_000);
        const n = countZigBlocks(src);
        var blocks: [n][]const u8 = undefined;
        var bi: usize = 0;
        var pos: usize = 0;
        while (bi < n) {
            pos = (std.mem.indexOfPos(u8, src, pos, "```zig") orelse unreachable) + "```zig".len;
            if (pos < src.len and src[pos] == '\r') pos += 1;
            if (pos < src.len and src[pos] == '\n') pos += 1;
            const start = pos;
            const end = std.mem.indexOfPos(u8, src, start, "\n```") orelse unreachable;
            blocks[bi] = src[start..end];
            pos = end + "\n```".len;
            bi += 1;
        }
        return blocks;
    }
}
