pub fn main() !void {
    std.log.info("@typeName(@TypeOf(c.foo)) is {s}", .{@typeName(@TypeOf(c.foo))});
    if (build_options.lazy) {
        std.log.info("foo at 0x{x}", .{@intFromPtr(solazy.functionRef(on_solazy_error, &solazy_funcs, "foo").load(.acquire))});
    }
    const foo_before = if (build_options.lazy) solazy.functionRef(on_solazy_error, &solazy_funcs, "foo").load(.acquire) else 0;

    std.log.info("calling foo (first time)...", .{});
    c.foo();
    std.log.info("foo returned", .{});

    if (build_options.lazy) {
        std.log.info("foo at 0x{x}", .{@intFromPtr(solazy.functionRef(on_solazy_error, &solazy_funcs, "foo").load(.acquire))});
        std.debug.assert(solazy.functionRef(on_solazy_error, &solazy_funcs, "foo").load(.acquire) != foo_before);
    }

    std.log.info("calling foo (second time)...", .{});
    c.foo();
    std.log.info("foo returned", .{});

    std.log.info("calling bar...", .{});
    c.bar();
    std.log.info("bar returned", .{});

    {
        std.log.info("calling theanswer...", .{});
        const result = c.theanswer();
        std.log.info("theanswer returned {}", .{result});
        std.debug.assert(result == 42);
    }

    {
        std.log.info("calling printi32 with 1058...", .{});
        c.printi32(1058);
        std.log.info("printi32 returned", .{});
    }

    std.debug.assert(0 == c.echoi32(0));
    std.debug.assert(1 == c.echoi32(1));
    std.debug.assert(-1 == c.echoi32(-1));

    // Test all argument counts 0–16. Each argsN function asserts
    // that every argument equals its parameter index, then returns N.
    std.debug.assert(0 == c.args0());
    std.debug.assert(1 == c.args1(0));
    std.debug.assert(2 == c.args2(0, 1));
    std.debug.assert(3 == c.args3(0, 1, 2));
    std.debug.assert(4 == c.args4(0, 1, 2, 3));
    std.debug.assert(5 == c.args5(0, 1, 2, 3, 4));
    std.debug.assert(6 == c.args6(0, 1, 2, 3, 4, 5));
    std.debug.assert(7 == c.args7(0, 1, 2, 3, 4, 5, 6));
    std.debug.assert(8 == c.args8(0, 1, 2, 3, 4, 5, 6, 7));
    std.debug.assert(9 == c.args9(0, 1, 2, 3, 4, 5, 6, 7, 8));
    std.debug.assert(10 == c.args10(0, 1, 2, 3, 4, 5, 6, 7, 8, 9));
    std.debug.assert(11 == c.args11(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
    std.debug.assert(12 == c.args12(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11));
    std.debug.assert(13 == c.args13(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12));
    std.debug.assert(14 == c.args14(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13));
    std.debug.assert(15 == c.args15(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14));
    std.debug.assert(16 == c.args16(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15));
}

const testso = struct {
    extern "test" fn foo() callconv(.c) void;
    extern "test" fn bar() callconv(.c) void;
    extern "test" fn theanswer() callconv(.c) i32;
    extern "test" fn printi32(i32) callconv(.c) void;
    extern "test" fn echoi32(i32) callconv(.c) i32;
    extern "test" fn args0() callconv(.c) i32;
    extern "test" fn args1(i32) callconv(.c) i32;
    extern "test" fn args2(i32, i32) callconv(.c) i32;
    extern "test" fn args3(i32, i32, i32) callconv(.c) i32;
    extern "test" fn args4(i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args5(i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args6(i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args7(i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args8(i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args9(i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args10(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args11(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args12(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args13(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args14(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args15(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
    extern "test" fn args16(i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32, i32) callconv(.c) i32;
};

pub fn nullterm(comptime s: []const u8) [s.len:0]u8 {
    var buf: [s.len:0]u8 = undefined;
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf;
}
const testso_lib = nullterm(build_options.testso);

const solazy = @import("solazy");

const solazy_funcs = [_]solazy.Func{
    .{ .lib = &testso_lib, .name = "foo", .Fn = @TypeOf(testso.foo) },
    .{ .lib = &testso_lib, .name = "bar", .Fn = @TypeOf(testso.bar) },
    .{ .lib = &testso_lib, .name = "theanswer", .Fn = @TypeOf(testso.theanswer) },
    .{ .lib = &testso_lib, .name = "printi32", .Fn = @TypeOf(testso.printi32) },
    .{ .lib = &testso_lib, .name = "echoi32", .Fn = @TypeOf(testso.echoi32) },
    .{ .lib = &testso_lib, .name = "args0", .Fn = @TypeOf(testso.args0) },
    .{ .lib = &testso_lib, .name = "args1", .Fn = @TypeOf(testso.args1) },
    .{ .lib = &testso_lib, .name = "args2", .Fn = @TypeOf(testso.args2) },
    .{ .lib = &testso_lib, .name = "args3", .Fn = @TypeOf(testso.args3) },
    .{ .lib = &testso_lib, .name = "args4", .Fn = @TypeOf(testso.args4) },
    .{ .lib = &testso_lib, .name = "args5", .Fn = @TypeOf(testso.args5) },
    .{ .lib = &testso_lib, .name = "args6", .Fn = @TypeOf(testso.args6) },
    .{ .lib = &testso_lib, .name = "args7", .Fn = @TypeOf(testso.args7) },
    .{ .lib = &testso_lib, .name = "args8", .Fn = @TypeOf(testso.args8) },
    .{ .lib = &testso_lib, .name = "args9", .Fn = @TypeOf(testso.args9) },
    .{ .lib = &testso_lib, .name = "args10", .Fn = @TypeOf(testso.args10) },
    .{ .lib = &testso_lib, .name = "args11", .Fn = @TypeOf(testso.args11) },
    .{ .lib = &testso_lib, .name = "args12", .Fn = @TypeOf(testso.args12) },
    .{ .lib = &testso_lib, .name = "args13", .Fn = @TypeOf(testso.args13) },
    .{ .lib = &testso_lib, .name = "args14", .Fn = @TypeOf(testso.args14) },
    .{ .lib = &testso_lib, .name = "args15", .Fn = @TypeOf(testso.args15) },
    .{ .lib = &testso_lib, .name = "args16", .Fn = @TypeOf(testso.args16) },
};

const c = if (!build_options.lazy) testso else solazy.namespace(on_solazy_error, &solazy_funcs);

fn on_solazy_error(
    kind: solazy.ErrorKind,
    lib: [:0]const u8,
    func: [:0]const u8,
) noreturn {
    switch (kind) {
        .lib => std.debug.panic(
            "load library '{s}' failed, error={f}",
            .{ lib, solazy.libError() },
        ),
        .sym => std.debug.panic(
            "load symbol '{s}' from library '{s}' failed, error={f}",
            .{ func, lib, solazy.symError() },
        ),
    }
}

const build_options = @import("build_options");
const std = @import("std");
