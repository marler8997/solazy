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

const c = solazy.wrap(&funcs, @This(), "solazy_vtable");

const solazy = @import("solazy");
const funcs = [_]solazy.Func{
    .{ .lib = "mylib", .name = "foo", .Fn = fn void() callconv(.c) },
    .{ .lib = "mylib", .name = "bar", .Fn = fn void(i32) callconv(.c) },
};

// public export of our vtable for the solazy module to access
// NOTE: you must include the type declaration to break the dependency loop
pub var solazy_vtable: solazy.Vtable(&solazy_funcs) = solazy.initVtable(
    &funcs,
    @This(),
    "solazy_vtable",
    on_solazy_error,
);

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
```

# TODO

- ability to customize string passed to dlopen/LoadLibraryA?
