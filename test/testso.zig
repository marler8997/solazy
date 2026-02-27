export fn foo() callconv(.c) void {
    std.debug.print("foo!\n", .{});
}
export fn bar() callconv(.c) void {
    std.debug.print("bar!\n", .{});
}

const std = @import("std");
