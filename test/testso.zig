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
    std.debug.print("printi32: {}\n", .{i});
}
export fn echoi32(i: i32) callconv(.c) i32 {
    return i;
}

export fn args0() callconv(.c) i32 {
    return 0;
}
export fn args1(a0: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    return 1;
}
export fn args2(a0: i32, a1: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    return 2;
}
export fn args3(a0: i32, a1: i32, a2: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    return 3;
}
export fn args4(a0: i32, a1: i32, a2: i32, a3: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    return 4;
}
export fn args5(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    return 5;
}
export fn args6(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    return 6;
}
export fn args7(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    return 7;
}
export fn args8(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    return 8;
}
export fn args9(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    return 9;
}
export fn args10(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    return 10;
}
export fn args11(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    return 11;
}
export fn args12(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32, a11: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    std.debug.assert(a11 == 11);
    return 12;
}
export fn args13(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32, a11: i32, a12: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    std.debug.assert(a11 == 11);
    std.debug.assert(a12 == 12);
    return 13;
}
export fn args14(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32, a11: i32, a12: i32, a13: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    std.debug.assert(a11 == 11);
    std.debug.assert(a12 == 12);
    std.debug.assert(a13 == 13);
    return 14;
}
export fn args15(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32, a11: i32, a12: i32, a13: i32, a14: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    std.debug.assert(a11 == 11);
    std.debug.assert(a12 == 12);
    std.debug.assert(a13 == 13);
    std.debug.assert(a14 == 14);
    return 15;
}
export fn args16(a0: i32, a1: i32, a2: i32, a3: i32, a4: i32, a5: i32, a6: i32, a7: i32, a8: i32, a9: i32, a10: i32, a11: i32, a12: i32, a13: i32, a14: i32, a15: i32) callconv(.c) i32 {
    std.debug.assert(a0 == 0);
    std.debug.assert(a1 == 1);
    std.debug.assert(a2 == 2);
    std.debug.assert(a3 == 3);
    std.debug.assert(a4 == 4);
    std.debug.assert(a5 == 5);
    std.debug.assert(a6 == 6);
    std.debug.assert(a7 == 7);
    std.debug.assert(a8 == 8);
    std.debug.assert(a9 == 9);
    std.debug.assert(a10 == 10);
    std.debug.assert(a11 == 11);
    std.debug.assert(a12 == 12);
    std.debug.assert(a13 == 13);
    std.debug.assert(a14 == 14);
    std.debug.assert(a15 == 15);
    return 16;
}

const std = @import("std");
