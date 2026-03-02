export fn foo2() callconv(.c) void {
    std.debug.print("inside foo2\n", .{});
}
const std = @import("std");
