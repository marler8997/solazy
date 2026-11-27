//! solazy — Lazy dynamic symbol binding for Zig
//!
//! Generates self-patching function pointers for shared library symbols.
//! On first call, the stub resolves the symbol via dlopen/dlsym (or
//! LdrLoadDll/LdrGetProcedureAddress on Windows), overwrites the pointer in-place,
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
    var names: [funcs.len][]const u8 = undefined;
    var types: [funcs.len]type = undefined;
    var attrs: [funcs.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (funcs, &names, &types, &attrs) |func, *name, *T, *attr| {
        const InlineFn = ThunkFn(func.Fn, .@"inline");
        const S = FnStorage(on_error, func);
        name.* = func.name;
        T.* = InlineFn;
        attr.* = .{
            .@"comptime" = true,
            .default_value_ptr = makeThunk(func.Fn, .@"inline", S.getReaderPtr),
        };
    }
    return @Struct(.auto, null, &names, &types, &attrs);
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
    err: Error,
) *const anyopaque {
    switch (kind) {
        .lib => std.debug.panic(
            "load library '{s}' failed, error={f}",
            .{ lib, err },
        ),
        .sym => std.debug.panic(
            "load symbol '{s}' from library '{s}' failed, error={f}",
            .{ func, lib, err },
        ),
    }
}

pub const ErrorKind = enum { lib, sym };

pub const OnError = struct {
    func: fn (
        kind: ErrorKind,
        lib: [:0]const u8,
        func: [:0]const u8,
        err: Error,
    ) *const anyopaque,

    pub const panic: OnError = .{ .func = defaultPanic };
};

fn resolve(
    comptime lib: [:0]const u8,
    func: [:0]const u8,
    comptime on_err: OnError,
) *const anyopaque {
    var err: Error = undefined;
    const lib_handle = LibStorage(lib).open(&err) orelse return on_err.func(.lib, lib, func, err);
    switch (builtin.os.tag) {
        .windows => {
            log.debug("LdrGetProcedureAddress '{s}'", .{func});
            var addr: *anyopaque = undefined;
            return switch (std.os.windows.ntdll.LdrGetProcedureAddress(lib_handle, &.initZ(func), 0, &addr)) {
                .SUCCESS => addr,
                else => |status| on_err.func(.sym, lib, func, .{ .data = status }),
            };
        },
        else => {
            log.debug("dlsym '{s}'", .{func});
            return os.dlsym(lib_handle, func) orelse on_err.func(.sym, lib, func, .{ .data = os.dlerror() });
        },
    }
}

const LibHandle = *anyopaque;

pub fn LibStorage(comptime lib: [:0]const u8) type {
    return struct {
        pub var global_handle: std.atomic.Value(?LibHandle) = .{ .raw = null };

        /// On failure, returns null and sets `err`.
        pub fn open(err: *Error) ?LibHandle {
            if (global_handle.load(.acquire)) |h| return h;
            const h: LibHandle = switch (builtin.os.tag) {
                .windows => h: {
                    log.debug("LdrLoadDll '{s}'", .{lib});
                    const lib_name: std.os.windows.UNICODE_STRING = comptime .initZ(std.unicode.utf8ToUtf16LeStringLiteral(lib));
                    var h: LibHandle = undefined;
                    switch (std.os.windows.ntdll.LdrLoadDll(null, null, &lib_name, &h)) {
                        .SUCCESS => break :h h,
                        else => |status| {
                            err.* = .{ .data = status };
                            return null;
                        },
                    }
                },
                else => h: {
                    log.debug("dlopen '{s}'", .{lib});
                    break :h os.dlopen(lib, .{ .LAZY = true }) orelse {
                        err.* = .{ .data = os.dlerror() };
                        return null;
                    };
                },
            };
            if (global_handle.cmpxchgStrong(null, h, .release, .monotonic)) |existing| {
                // Another thread won the race — drop our redundant refcount.
                switch (builtin.os.tag) {
                    .windows => {
                        const status = std.os.windows.ntdll.LdrUnloadDll(h);
                        std.debug.assert(status == .SUCCESS);
                    },
                    else => {
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

fn ThunkFn(comptime Fn: type, comptime cc_override: ?std.lang.CallingConvention) type {
    const info = @typeInfo(Fn).@"fn";
    if (info.is_generic) @compileError("generic functions not supported: '" ++ @typeName(Fn) ++ "'");
    var param_types: [info.param_types.len]type = undefined;
    for (info.param_types, &param_types) |opt_T, *T| T.* = opt_T.?;
    return @Fn(
        &param_types,
        info.param_attrs[0..info.param_types.len],
        info.return_type.?,
        .{ .@"callconv" = cc_override orelse info.attrs.@"callconv" },
    );
}

fn makeThunk(
    comptime Fn: type,
    comptime cc_override: ?std.lang.CallingConvention,
    comptime getPtr: fn () *const Fn,
) *const ThunkFn(Fn, cc_override) {
    const info = @typeInfo(Fn).@"fn";
    const P = info.param_types;
    const R = info.return_type orelse
        @compileError("generic return type not supported for '" ++ @typeName(Fn) ++ "'");
    const cc = cc_override orelse info.attrs.@"callconv";
    return switch (P.len) {
        0 => &(struct {
            fn f() callconv(cc) R {
                return @call(.auto, getPtr(), .{});
            }
        }).f,
        1 => &(struct {
            fn f(a0: P[0].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{a0});
            }
        }).f,
        2 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1 });
            }
        }).f,
        3 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2 });
            }
        }).f,
        4 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3 });
            }
        }).f,
        5 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4 });
            }
        }).f,
        6 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5 });
            }
        }).f,
        7 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6 });
            }
        }).f,
        8 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7 });
            }
        }).f,
        9 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8 });
            }
        }).f,
        10 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9 });
            }
        }).f,
        11 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 });
            }
        }).f,
        12 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?, a11: P[11].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 });
            }
        }).f,
        13 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?, a11: P[11].?, a12: P[12].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 });
            }
        }).f,
        14 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?, a11: P[11].?, a12: P[12].?, a13: P[13].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 });
            }
        }).f,
        15 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?, a11: P[11].?, a12: P[12].?, a13: P[13].?, a14: P[14].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 });
            }
        }).f,
        16 => &(struct {
            fn f(a0: P[0].?, a1: P[1].?, a2: P[2].?, a3: P[3].?, a4: P[4].?, a5: P[5].?, a6: P[6].?, a7: P[7].?, a8: P[8].?, a9: P[9].?, a10: P[10].?, a11: P[11].?, a12: P[12].?, a13: P[13].?, a14: P[14].?, a15: P[15].?) callconv(cc) R {
                return @call(.auto, getPtr(), .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15 });
            }
        }).f,
        else => @compileError("TODO: support functions with more than 16 parameters for '" ++ @typeName(Fn) ++ "'"),
    };
}

/// The error from a failed library load or symbol lookup, passed to `OnError`.
/// On posix this points into libc's `dlerror` buffer, which is only valid until
/// the next `dl*` call on the same thread, so format or copy it before doing
/// anything that could load a library or resolve a symbol (including calling
/// another lazy function).
pub const Error = struct {
    data: switch (builtin.os.tag) {
        .windows => std.os.windows.NTSTATUS,
        else => ?[*:0]u8,
    },
    pub fn format(e: Error, writer: *std.Io.Writer) error{WriteFailed}!void {
        switch (builtin.os.tag) {
            .windows => try writer.print("NTSTATUS 0x{X:0>8}", .{@backingInt(e.data)}),
            else => try writer.print("{?s}", .{e.data}),
        }
    }
};

pub const os = if (builtin.os.tag == .windows) struct {} else struct {
    pub extern fn dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) ?*anyopaque;
    pub extern fn dlclose(handle: *anyopaque) c_int;
    pub extern fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    pub extern fn dlerror() ?[*:0]u8;
};

const log = std.log.scoped(.solazy);

const builtin = @import("builtin");
const std = @import("std");
