pub fn main() !void {
    std.log.info("@typeName(@TypeOf(c.foo)) is {s}", .{@typeName(@TypeOf(c.foo))});
    if (build_options.lazy) {
        std.log.info("foo at 0x{x}", .{@intFromPtr(solazy_vtable.foo.load(.acquire))});
    }
    const foo_before = if (build_options.lazy) solazy_vtable.foo.load(.acquire) else 0;

    std.log.info("calling foo (first time)...", .{});
    c.foo();
    std.log.info("foo returned", .{});

    if (build_options.lazy) {
        std.log.info("foo at 0x{x}", .{@intFromPtr(solazy_vtable.foo.load(.acquire))});
        std.debug.assert(solazy_vtable.foo.load(.acquire) != foo_before);
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
}

const testso = struct {
    extern "test" fn foo() callconv(.c) void;
    extern "test" fn bar() callconv(.c) void;
    extern "test" fn theanswer() callconv(.c) i32;
    extern "test" fn printi32(i32) callconv(.c) void;
    extern "test" fn echoi32(i32) callconv(.c) i32;
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
};

// NOTE: you must include the type declaration to break the dependency loop
pub var solazy_vtable: solazy.Vtable(&solazy_funcs) = solazy.initVtable(&solazy_funcs, @This(), "solazy_vtable", on_solazy_error);

const c = if (build_options.lazy) solazy.wrap(&solazy_funcs, @This(), "solazy_vtable") else testso;

fn on_solazy_error(
    kind: solazy.ErrorKind,
    lib: [:0]const u8,
    func: [:0]const u8,
) noreturn {
    switch (kind) {
        .lib => std.debug.panic("load library '{s}' failed", .{lib}),
        .sym => std.debug.panic(
            "load symbol '{s}' from library '{s}' failed, error={f}",
            .{ func, lib, solazy.symError() },
        ),
    }
}

const build_options = @import("build_options");
const std = @import("std");
