# solazy — Lazy dynamic symbol binding for Zig

Self-patching function pointers for shared library symbols.
On first call, the stub resolves the symbol via dlopen/dlsym (or
LoadLibraryA/GetProcAddress on windows), overwrites
the pointer in-place, and tail-calls the resolved function. Subsequent
calls go directly through the patched pointer, no branches, no checks.
Functions are lock-free and thread safe.

# Example Usage

```zig
pub fn main() void {
    c.foo();
    c.bar(0);
}

const solazy = @import("solazy");
const c = solazy.namespace(.panic, &.{
    .{ .lib = "mylib", .name = "foo", .Fn = fn () callconv(.c) void },
    .{ .lib = "mylib", .name = "bar", .Fn = fn (i32) callconv(.c) void },
});

const std = @import("std");
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
- instead of just "noreturn", specify a return value or possibly fallback function pointer on error
