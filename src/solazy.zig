//! solazy — Lazy dynamic symbol binding for Zig
//!
//! Generates self-patching function pointers for shared library symbols.
//! On first call, the stub resolves the symbol via dlopen/dlsym, overwrites
//! the pointer in-place, and tail-calls the resolved function. Subsequent
//! calls go directly through the patched pointer — no branches, no checks.

pub const Func = struct {
    lib: [:0]const u8,
    name: [:0]const u8,
    /// The function type (not a pointer to a function).
    Fn: type,
};

pub fn Vtable(comptime funcs: []const Func) type {
    var fields: [funcs.len]std.builtin.Type.StructField = undefined;
    for (funcs, &fields) |func, *field| {
        const T = std.atomic.Value(*const func.Fn);
        field.* = .{
            .name = func.name,
            .type = T,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(T),
        };
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn initVtable(
    comptime funcs: []const Func,
    comptime vtable_namespace: type,
    comptime vtable_decl_name: []const u8,
    comptime on_error: OnError,
) Vtable(funcs) {
    const vtable = &@field(vtable_namespace, vtable_decl_name);
    var result: Vtable(funcs) = undefined;
    inline for (funcs) |func| {
        @field(result, func.name) = .{ .raw = loaderFn(func, vtable, on_error) };
    }
    return result;
}

fn resolve(
    comptime lib: [:0]const u8,
    func: [:0]const u8,
    on_err: OnError,
) *const anyopaque {
    const h = cachedDlopen(lib) orelse on_err(.lib, lib, func);
    if (builtin.os.tag == .windows) {
        log.debug("GetProcAddress '{s}'", .{func});
        return @ptrCast(std.os.windows.kernel32.GetProcAddress(@ptrCast(h), func) orelse
            on_err(.lib, lib, func));
    } else {
        log.debug("dlsym '{s}'", .{func});
        return os.dlsym(h, func) orelse on_err(.sym, lib, func);
    }
}

pub fn cachedDlopen(comptime lib: [:0]const u8) ?*anyopaque {
    const S = struct {
        var handle: std.atomic.Value(?*anyopaque) = .{ .raw = null };
    };
    if (S.handle.load(.acquire)) |h| return h;
    log.debug("dlopen '{s}'", .{lib});
    if (builtin.os.tag == .windows) {
        const h: *anyopaque = @ptrCast(os.LoadLibraryA(lib) orelse return null);
        if (S.handle.cmpxchgStrong(null, h, .release, .acquire)) |existing| {
            const r = std.os.windows.kernel32.FreeLibrary(@ptrCast(h));
            std.debug.assert(r != 0);
            return existing;
        }
        return h;
    } else {
        const h = os.dlopen(lib, .{ .LAZY = true }) orelse return null;
        if (S.handle.cmpxchgStrong(null, h, .release, .acquire)) |existing| {
            // Another thread won the race — drop our redundant refcount.
            const result = os.dlclose(h);
            std.debug.assert(result == 0);
            return existing;
        }
        return h;
    }
}

fn loaderFn(comptime func: Func, vtable: anytype, on_err: OnError) *const func.Fn {
    return makeThunk(func.Fn, null, (struct {
        fn getPtr() *const func.Fn {
            const ptr = resolve(func.lib, func.name, on_err);
            @field(vtable, func.name).store(@ptrCast(@alignCast(ptr)), .release);
            return @ptrCast(@alignCast(ptr));
        }
    }).getPtr);
}

pub const ErrorKind = enum { lib, sym };

// TODO: change this to a vtable, one for each return type
//       so the caller can choose to return
pub const OnError = fn (
    kind: ErrorKind,
    lib: [:0]const u8,
    func: [:0]const u8,
) noreturn;

pub fn wrap(
    comptime funcs: []const Func,
    comptime vtable_namespace: type,
    comptime vtable_decl_name: []const u8,
) Wrap(funcs, vtable_namespace, vtable_decl_name) {
    return .{};
}

pub fn Wrap(
    comptime funcs: []const Func,
    comptime vtable_namespace: type,
    comptime vtable_decl_name: []const u8,
) type {
    const vtable = comptime &@field(vtable_namespace, vtable_decl_name);
    var fields: [funcs.len]std.builtin.Type.StructField = undefined;
    for (funcs, fields[0..funcs.len]) |func, *field| {
        const InlineFn = ThunkFn(func.Fn, .@"inline");
        field.* = .{
            .name = func.name,
            .type = InlineFn,
            .default_value_ptr = @ptrCast(makeThunk(func.Fn, .@"inline", (struct {
                fn getPtr() *const func.Fn {
                    return @ptrCast(@field(vtable, func.name).load(.acquire));
                }
            }).getPtr)),
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
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{});
            }
        }).f,
        1 => &(struct {
            fn f(a0: P[0].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{a0});
            }
        }).f,
        2 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{ a0, a1 });
            }
        }).f,
        3 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{ a0, a1, a2 });
            }
        }).f,
        4 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{ a0, a1, a2, a3 });
            }
        }).f,
        5 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{ a0, a1, a2, a3, a4 });
            }
        }).f,
        6 => &(struct {
            fn f(a0: P[0].type.?, a1: P[1].type.?, a2: P[2].type.?, a3: P[3].type.?, a4: P[4].type.?, a5: P[5].type.?) callconv(cc) R {
                return @call(.auto, @as(*const Fn, @ptrCast(@alignCast(getPtr()))), .{ a0, a1, a2, a3, a4, a5 });
            }
        }).f,
        else => @compileError("TODO: support functions with more than 6 parameters for '" ++ @typeName(Fn) ++ "'"),
    };
}

pub fn symError() SymError {
    return switch (builtin.os.tag) {
        .windows => .{ .data = @intFromEnum(std.os.windows.GetLastError()) },
        else => .{ .data = os.dlerror() },
    };
}
pub const SymError = struct {
    data: switch (builtin.os.tag) {
        .windows => u32,
        else => ?[*:0]u8,
    },
    pub fn format(e: SymError, writer: *std.Io.Writer) error{WriteFailed}!void {
        switch (builtin.os.tag) {
            .windows => try writer.print("{d}", .{e.data}),
            else => try writer.print("{?s}", .{e.data}),
        }
    }
};

const os = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.winapi) ?std.os.windows.HMODULE;
} else struct {
    extern fn dlopen(path: ?[*:0]const u8, mode: std.c.RTLD) ?*anyopaque;
    extern fn dlclose(handle: *anyopaque) c_int;
    extern fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    extern fn dlerror() ?[*:0]u8;
};

const log = std.log.scoped(.solazy);

const builtin = @import("builtin");
const std = @import("std");
