//! solazy — Lazy dynamic symbol binding for Zig
//!
//! Generates self-patching function pointers for shared library symbols.
//! On first call, the stub resolves the symbol via dlopen/dlsym (or
//! LoadLibraryA/GetProcAddress on Windows), overwrites the pointer in-place,
//! and tail-calls the resolved function. Subsequent calls go directly through
//! the patched pointer, no branches, no checks.

/// Creates a "namespace" to call lazy functions on. However, since zig cannot
/// reify declarations, it's actually a struct with an inline comptime field
/// for each function. These comptime functions forward the call to the current
/// function pointer which is swapped out after the first call to the one loaded from
/// the library.
pub fn namespace(
    comptime on_error: OnError,
    comptime funcs: []const Func,
) Namespace(on_error, funcs) {
    return .{};
}

fn Namespace(comptime on_error: OnError, comptime funcs: []const Func) type {
    var fields: [funcs.len]std.builtin.Type.StructField = undefined;
    for (funcs, fields[0..funcs.len]) |func, *field| {
        const InlineFn = ThunkFn(func.Fn, .@"inline");
        const S = FnStorage(on_error, func);
        field.* = .{
            .name = func.name,
            .type = InlineFn,
            .default_value_ptr = makeThunk(func.Fn, .@"inline", S.getReaderPtr),
            .is_comptime = true,
            .alignment = @alignOf(InlineFn),
        };
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

/// Provides access to the underlying global function pointer.
pub fn globalFunctionRef(
    comptime on_error: OnError,
    comptime funcs: []const Func,
    comptime name: []const u8,
) *std.atomic.Value(*const findFunc(funcs, name).Fn) {
    return &FnStorage(on_error, findFunc(funcs, name)).global_ptr;
}

fn findFunc(comptime funcs: []const Func, comptime name: []const u8) Func {
    for (funcs) |func| {
        if (std.mem.eql(u8, func.name, name)) return func;
    }
    @compileError("no function named '" ++ name ++ "'");
}

fn FnStorage(comptime on_error: OnError, comptime func: Func) type {
    return struct {
        var global_ptr: std.atomic.Value(*const func.Fn) = .{
            .raw = makeThunk(func.Fn, null, getLoaderPtr),
        };

        fn getLoaderPtr() *const func.Fn {
            const resolved_ptr = resolve(func.lib, func.name, on_error);
            const typed: *const func.Fn = @ptrCast(@alignCast(resolved_ptr));
            global_ptr.store(typed, .release);
            return typed;
        }

        fn getReaderPtr() *const func.Fn {
            return global_ptr.load(.acquire);
        }
    };
}

pub const Func = struct {
    lib: [:0]const u8,
    name: [:0]const u8,
    /// The function type (not a pointer to a function).
    Fn: type,
};

pub fn defaultPanic(
    kind: ErrorKind,
    lib: [:0]const u8,
    func: [:0]const u8,
) *const anyopaque {
    switch (kind) {
        .lib => std.debug.panic(
            "load library '{s}' failed, error={f}",
            .{ lib, libError() },
        ),
        .sym => std.debug.panic(
            "load symbol '{s}' from library '{s}' failed, error={f}",
            .{ func, lib, symError() },
        ),
    }
}

pub const ErrorKind = enum { lib, sym };

pub const OnError = struct {
    func: fn (
        kind: ErrorKind,
        lib: [:0]const u8,
        func: [:0]const u8,
    ) *const anyopaque,

    pub const panic: OnError = .{ .func = defaultPanic };
};

fn resolve(
    comptime lib: [:0]const u8,
    func: [:0]const u8,
    comptime on_err: OnError,
) *const anyopaque {
    const lib_handle = LibStorage(lib).open() orelse return on_err.func(.lib, lib, func);
    const load_func_name, const load_func = switch (builtin.os.tag) {
        .windows => .{ "GetProcAddress", std.os.windows.kernel32.GetProcAddress },
        else => .{ "dlsym", os.dlsym },
    };
    log.debug(load_func_name ++ " '{s}'", .{func});
    return load_func(lib_handle, func) orelse return on_err.func(.sym, lib, func);
}

const LibHandle = switch (builtin.os.tag) {
    .windows => std.os.windows.HMODULE,
    else => *anyopaque,
};

pub fn LibStorage(comptime lib: [:0]const u8) type {
    return struct {
        pub var global_handle: std.atomic.Value(?LibHandle) = .{ .raw = null };

        pub fn open() ?LibHandle {
            if (global_handle.load(.acquire)) |h| return h;
            const load_func_name = switch (builtin.os.tag) {
                .windows => "LoadLibrary",
                else => "dlopen",
            };
            log.debug(load_func_name ++ " '{s}'", .{lib});
            const h = switch (builtin.os.tag) {
                .windows => os.LoadLibraryA(lib) orelse return null,
                else => os.dlopen(lib, .{ .LAZY = true }) orelse return null,
            };
            if (global_handle.cmpxchgStrong(null, h, .release, .acquire)) |existing| {
                switch (builtin.os.tag) {
                    .windows => {
                        const r = std.os.windows.kernel32.FreeLibrary(h);
                        std.debug.assert(r != 0);
                    },
                    else => {
                        // Another thread won the race — drop our redundant refcount.
                        const result = os.dlclose(h);
                        std.debug.assert(result == 0);
                    },
                }
                return existing;
            }
            return h;
        }
    };
}

fn ThunkFn(comptime Fn: type, comptime cc_override: ?std.builtin.CallingConvention) type {
    const info = @typeInfo(Fn).@"fn";
    return @Type(std.builtin.Type{ .@"fn" = .{
        .calling_convention = cc_override orelse info.calling_convention,
        .is_generic = false,
        .is_var_args = false,
        .return_type = info.return_type,
        .params = info.params,
    } });
}

fn makeThunk(
    comptime Fn: type,
    comptime cc_override: ?std.builtin.CallingConvention,
    comptime getPtr: fn () *const Fn,
) *const ThunkFn(Fn, cc_override) {
    const info = @typeInfo(Fn).@"fn";
    const P = info.params;
    const R = info.return_type orelse
        @compileError("generic return type not supported for '" ++ @typeName(Fn) ++ "'");
    const cc = cc_override orelse info.calling_convention;
    return switch (P.len) {
        0 => &(struct {
            fn f() callconv(cc) R {
                return @call(.auto, getPtr(), .{});
            }
        }).f,
        1 => &(struct {
            fn f(a0: P[0].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{a0});
            }
        }).f,
        2 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1 });
            }
        }).f,
        3 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2 });
            }
        }).f,
        4 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3 });
            }
        }).f,
        5 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4 });
            }
        }).f,
        6 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5 });
            }
        }).f,
        7 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6 });
            }
        }).f,
        8 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7 });
            }
        }).f,
        9 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8 });
            }
        }).f,
        10 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9 });
            }
        }).f,
        11 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 });
            }
        }).f,
        12 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?, a11: P[11].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 });
            }
        }).f,
        13 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?, a11: P[11].type.?, a12: P[12].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 });
            }
        }).f,
        14 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?, a11: P[11].type.?, a12: P[12].type.?, a13: P[13].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 });
            }
        }).f,
        15 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?, a11: P[11].type.?, a12: P[12].type.?, a13: P[13].type.?, a14: P[14].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 });
            }
        }).f,
        16 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?, a6: P[6].type.?, a7: P[7].type.?, a8: P[8].type.?, a9: P[9].type.?, a10: P[10].type.?, a11: P[11].type.?, a12: P[12].type.?, a13: P[13].type.?, a14: P[14].type.?, a15: P[15].type.?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15 });
            }
        }).f,
        else => @compileError("TODO: support functions with more than 16 parameters for '" ++ @typeName(Fn) ++ "'"),
    };
}

pub const Error = struct {
    data: switch (builtin.os.tag) {
        .windows => u32,
        else => ?[*:0]u8,
    },
    pub fn format(e: Error, writer: *std.Io.Writer) error{WriteFailed}!void {
        switch (builtin.os.tag) {
            .windows => try writer.print("{d}", .{e.data}),
            else => try writer.print("{?s}", .{e.data}),
        }
    }
};

pub fn libError() Error {
    return switch (builtin.os.tag) {
        .windows => .{ .data = @intFromEnum(std.os.windows.GetLastError()) },
        else => .{ .data = os.dlerror() },
    };
}

pub fn symError() Error {
    return switch (builtin.os.tag) {
        .windows => .{ .data = @intFromEnum(std.os.windows.GetLastError()) },
        else => .{ .data = os.dlerror() },
    };
}

pub const os = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.winapi) ?std.os.windows.HMODULE;
} else struct {
    pub extern fn dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) ?*anyopaque;
    pub extern fn dlclose(handle: *anyopaque) c_int;
    pub extern fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    pub extern fn dlerror() ?[*:0]u8;
};

const log = std.log.scoped(.solazy);

const builtin = @import("builtin");
const std = @import("std");
