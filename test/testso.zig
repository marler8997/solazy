export fn foo() callconv(.c) void {
    std.debug.print("inside foo\n", .{});
}
export fn bar() callconv(.c) void {
    std.debug.print("inside bar\n", .{});
}
export fn theanswer() callconv(.c) i32 {
    std.debug.print("inside theanswer\n", .{});
    return 42;
}
export fn printi32(i: i32) callconv(.c) void {
    std.debug.print("print32: {}\n", .{i});
}
export fn echoi32(i: i32) callconv(.c) i32 {
    return i;
}

const std = @import("std");
