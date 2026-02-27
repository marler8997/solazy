pub fn main() !void {
    std.log.info("calling foo...", .{});
    c.foo();
    std.log.info("foo called!", .{});
    std.log.info("calling bar...", .{});
    c.bar();
    std.log.info("bar called!", .{});
}

const testso = struct {
    extern "test" fn foo() callconv(.c) void;
    extern "test" fn bar() callconv(.c) void;
};

const c = if (build_options.lazy) @import("solazy").wrap(&.{
    // TODO: can we just pass in testso.foo and testso.bar
    .{ .lib = "test", .name = "foo" },
    .{ .lib = "test", .name = "bar" },
    // .foo = testso.foo,
    // .bar = testso.bar,
}) else testso;

const build_options = @import("build_options");
const std = @import("std");
