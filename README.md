# solazy 

Lazy shared libraries.

- self-patching functions pointers
- thread safe/lock free

# Example Usage

```zig
const solazy = @import("solazy");

const rl = solazy.namespace(.panic, &.{
    .{ .lib = "raylib", .name = "InitWindow", .Fn = fn (i32, i32, [*:0]const u8) callconv(.c) void },
    .{ .lib = "raylib", .name = "WindowShouldClose", .Fn = fn () callconv(.c) bool },
    .{ .lib = "raylib", .name = "ClearBackground", .Fn = fn (u32) callconv(.c) void },
    .{ .lib = "raylib", .name = "BeginDrawing", .Fn = fn () callconv(.c) void },
    .{ .lib = "raylib", .name = "EndDrawing", .Fn = fn () callconv(.c) void },
    .{ .lib = "raylib", .name = "CloseWindow", .Fn = fn () callconv(.c) void },
});

pub fn main() void {
    rl.InitWindow(800, 450, "solazy example");
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        rl.ClearBackground(0xf5f5f5ff);
        rl.EndDrawing();
    }
    rl.CloseWindow();
}
```


The example above is configured to panic on missing libraries/functions, but you can also provide your own fallback:

```zig
pub fn main() void {
    const result = c.foo();
    std.debug.assert(result == 0x24118434);
}

const solazy = @import("solazy");
const c = solazy.namespace(.{ .func = solazy_fallback }, &.{
    .{ .lib = "mylib", .name = "foo", .Fn = fn () callconv(.c) u32 },
});

fn foo_fallback() callconv(.c) u32 {
    return 0x24118434;
}
fn solazy_fallback(kind: solazy.ErrorKind, lib: [:0]const u8, func: [:0]const u8) *const anyopaque {
    std.debug.assert(kind == .lib);
    std.debug.assert(std.mem.eql(u8, lib, "mylib"));
    std.debug.assert(std.mem.eql(u8, func, "foo"));
    return &foo_fallback;
}

const std = @import("std");
```

# TODO

- customize string passed to dlopen/LoadLibraryA at runtime?
