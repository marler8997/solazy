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
const c = solazy.namespace(on_solazy_error, &.{
    .{ .lib = "mylib", .name = "foo", .Fn = fn () callconv(.c) void },
    .{ .lib = "mylib", .name = "bar", .Fn = fn (i32) callconv(.c) void },
});

// choose how to handle missing libraries/symbols
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

const std = @import("std");
```

# TODO

- customize string passed to dlopen/LoadLibraryA at runtime?
- instead of just "noreturn", specify a return value or possibly fallback function pointer on error
