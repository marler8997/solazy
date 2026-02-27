//! solazy — Lazy dynamic symbol binding for Zig
//!
//! Generates self-patching function pointers for shared library symbols.
//! On first call, the stub resolves the symbol via dlopen/dlsym, overwrites
//! the pointer in-place, and tail-calls the resolved function. Subsequent
//! calls go directly through the patched pointer — no branches, no checks.
//!
//! When built with the LLVM backend, uses architecture-specific naked
//! trampolines that are completely signature-agnostic. When built with
//! the self-hosted backend (whose assembler is more limited), falls back
//! to comptime-generated stubs that forward arguments explicitly.
//!
//! Both paths produce identical runtime behavior: a self-patching `*FnPtr`
//! with zero overhead after first call.
//!
//! ## Example
//!
//! ```zig
//! const solazy = @import("solazy");
//!
//! const puts = solazy.lazy("libc.so.6", "puts",
//!     *const fn ([*:0]const u8) callconv(.c) c_int,
//! );
//!
//! pub fn main() void {
//!     _ = puts.*("first call — resolves, patches, calls");
//!     _ = puts.*("second call — direct, zero overhead");
//! }
//! ```

pub const Func = struct {
    lib: [:0]const u8,
    name: [:0]const u8,
    // TODO: type
};

fn Wrap(comptime funcs: []const Func) type {
    var fields: [funcs.len]std.builtin.Type.StructField = undefined;
    for (funcs, &fields) |func, *field| {
        const Field = fn () void;
        field.* = .{
            .name = func.name,
            .type = Field,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Field),
        };
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub fn wrap(comptime funcs: []const Func) Wrap(funcs) {
    return .{
        .foo = (struct {
            fn foo() void {
                std.log.err("TODO: call foo!", .{});
            }
        }).foo,
        .bar = (struct {
            fn bar() void {
                std.log.err("TODO: call bar!", .{});
            }
        }).bar,
    };
}

/// True when the LLVM backend is in use, giving us access to a full assembler.
const has_llvm_asm = builtin.zig_backend == .stage2_llvm;

/// Create a lazily-resolved, self-patching function pointer.
///
/// Returns `*FnPtr` — a pointer to a mutable function pointer slot. The slot
/// initially points to a resolver stub. On first call through `ptr.*( args... )`:
///
///   1. The stub resolves the real symbol via dlopen + dlsym
///   2. Overwrites the slot in-place with the resolved address
///   3. Tail-calls the resolved function with the original arguments
///
/// After that, the slot points directly at the real symbol. Subsequent calls
/// are a plain indirect call — zero overhead.
///
/// `FnPtr` must be a function pointer type: `*const fn(args...) callconv(.c) T`
///
pub fn lazy(
    comptime lib_name: [*:0]const u8,
    comptime sym_name: [*:0]const u8,
    comptime FnPtr: type,
) *FnPtr {
    validateFnPtr(FnPtr);
    const S = LazySlot(lib_name, sym_name, FnPtr);
    return &S.ptr;
}

/// Eagerly resolve a symbol right now. Returns an error on failure.
pub fn eagerResolve(
    lib_name: [*:0]const u8,
    sym_name: [*:0]const u8,
    comptime FnPtr: type,
) error{ DlopenFailed, DlsymFailed }!FnPtr {
    validateFnPtr(FnPtr);
    return doResolve(lib_name, sym_name, FnPtr);
}

// ============================================================================
// Validation
// ============================================================================

fn validateFnPtr(comptime FnPtr: type) void {
    const ptr_info = switch (@typeInfo(FnPtr)) {
        .pointer => |p| p,
        else => @compileError(
            "solazy: expected a function pointer type like " ++
                "*const fn(...) callconv(.c) T, got: " ++ @typeName(FnPtr),
        ),
    };
    switch (@typeInfo(ptr_info.child)) {
        .@"fn" => |f| {
            if (f.is_var_args)
                @compileError("solazy: variadic functions not supported");
            if (!has_llvm_asm and f.params.len > 12)
                @compileError("solazy: functions with more than 12 parameters not supported (self-hosted backend)");
        },
        else => @compileError(
            "solazy: pointed-to type must be a function, got: " ++ @typeName(ptr_info.child),
        ),
    }
}

// ============================================================================
// Resolution
// ============================================================================

fn doResolve(
    lib_name: [*:0]const u8,
    sym_name: [*:0]const u8,
    comptime FnPtr: type,
) error{ DlopenFailed, DlsymFailed }!FnPtr {
    const handle = std.c.dlopen(lib_name, .{ .LAZY = true }) orelse
        return error.DlopenFailed;
    const raw = std.c.dlsym(handle, sym_name) orelse
        return error.DlsymFailed;
    return @ptrCast(raw);
}

fn resolveOrPanic(
    comptime lib_name: [*:0]const u8,
    comptime sym_name: [*:0]const u8,
    comptime FnPtr: type,
) FnPtr {
    return doResolve(lib_name, sym_name, FnPtr) catch |err| switch (err) {
        error.DlopenFailed => std.debug.panic(
            "solazy: dlopen '{s}' failed",
            .{std.mem.span(lib_name)},
        ),
        error.DlsymFailed => std.debug.panic(
            "solazy: dlsym '{s}' for library '{s}' failed",
            .{ std.mem.span(sym_name), std.mem.span(lib_name) },
        ),
    };
}

// ============================================================================
// Lazy slot: dispatch to asm or fallback
// ============================================================================

fn LazySlot(
    comptime lib_name: [*:0]const u8,
    comptime sym_name: [*:0]const u8,
    comptime FnPtr: type,
) type {
    if (has_llvm_asm) {
        return AsmSlot(lib_name, sym_name, FnPtr);
    } else {
        return FallbackSlot(lib_name, sym_name, FnPtr);
    }
}

// ############################################################################
//
//  LLVM backend: naked asm trampolines
//
//  The trampoline is completely signature-agnostic. It saves the entire
//  C ABI argument state (integer + FP registers), calls the resolver
//  which patches `ptr` and returns the resolved address, restores all
//  argument registers, and tail-jumps. One stub works for ANY arity/types.
//
//  After patching, `ptr` points directly at the real symbol.
//
// ############################################################################

fn AsmSlot(
    comptime lib_name: [*:0]const u8,
    comptime sym_name: [*:0]const u8,
    comptime FnPtr: type,
) type {
    return struct {
        pub var ptr: FnPtr = @ptrCast(&trampoline);

        /// Called by the trampoline. Resolves the real symbol, patches `ptr`,
        /// and returns the resolved address so the trampoline can jump to it.
        fn resolveAndPatch() callconv(.c) usize {
            const resolved = resolveOrPanic(lib_name, sym_name, FnPtr);
            ptr = resolved;
            return @intFromPtr(resolved);
        }

        fn trampoline() callconv(.naked) noreturn {
            switch (builtin.cpu.arch) {
                // =============================================================
                // x86_64 — System V AMD64 ABI
                //
                // Integer args:  rdi, rsi, rdx, rcx, r8, r9
                // FP args:       xmm0–xmm7
                // Return:        rax (+ rdx for wide returns)
                // Scratch:       r10, r11 (caller-saved, not args)
                //
                // Stack alignment on entry (via `call *ptr`): RSP ≡ 8 (mod 16)
                //   6 pushq = 48 bytes  →  RSP ≡ 56 ≡ 8 (mod 16)
                //   sub $0x88 = 136     →  RSP ≡ 192 ≡ 0 (mod 16) ✓
                // =============================================================
                .x86_64 => asm volatile (
                // --- Save integer argument registers ---
                    \\ pushq   %%rdi
                    \\ pushq   %%rsi
                    \\ pushq   %%rdx
                    \\ pushq   %%rcx
                    \\ pushq   %%r8
                    \\ pushq   %%r9
                    //
                    // --- Save FP argument registers (128 bytes + 8 padding) ---
                    \\ subq    $0x88, %%rsp
                    \\ movaps  %%xmm0, 0x00(%%rsp)
                    \\ movaps  %%xmm1, 0x10(%%rsp)
                    \\ movaps  %%xmm2, 0x20(%%rsp)
                    \\ movaps  %%xmm3, 0x30(%%rsp)
                    \\ movaps  %%xmm4, 0x40(%%rsp)
                    \\ movaps  %%xmm5, 0x50(%%rsp)
                    \\ movaps  %%xmm6, 0x60(%%rsp)
                    \\ movaps  %%xmm7, 0x70(%%rsp)
                    //
                    // --- Call resolver (patches ptr, returns address in rax) ---
                    \\ callq   %[resolve]
                    //
                    // --- Stash resolved address in r11 (scratch, not an arg) ---
                    \\ movq    %%rax, %%r11
                    //
                    // --- Restore FP argument registers ---
                    \\ movaps  0x00(%%rsp), %%xmm0
                    \\ movaps  0x10(%%rsp), %%xmm1
                    \\ movaps  0x20(%%rsp), %%xmm2
                    \\ movaps  0x30(%%rsp), %%xmm3
                    \\ movaps  0x40(%%rsp), %%xmm4
                    \\ movaps  0x50(%%rsp), %%xmm5
                    \\ movaps  0x60(%%rsp), %%xmm6
                    \\ movaps  0x70(%%rsp), %%xmm7
                    \\ addq    $0x88, %%rsp
                    //
                    // --- Restore integer argument registers ---
                    \\ popq    %%r9
                    \\ popq    %%r8
                    \\ popq    %%rcx
                    \\ popq    %%rdx
                    \\ popq    %%rsi
                    \\ popq    %%rdi
                    //
                    // --- Tail-jump to resolved function ---
                    // All arg registers restored. Return address still on stack
                    // from the original caller's `call *ptr`.
                    \\ jmpq    *%%r11
                    :
                    : [resolve] "X" (&resolveAndPatch),
                ),

                // =============================================================
                // aarch64 — AAPCS64
                //
                // Integer args:  x0–x7
                // FP args:       q0–q7 (128-bit SIMD/FP registers)
                // Return:        x0 (+ x1 for wide returns)
                // LR:            x30
                // Scratch:       x16, x17 (IP0/IP1)
                //
                // Stack: 16-byte aligned at all times.
                // =============================================================
                .aarch64 => asm volatile (
                // Save frame pointer + link register
                    \\ stp     x29, x30, [sp, #-16]!
                    //
                    // Save integer argument registers (x0–x7)
                    \\ stp     x0,  x1,  [sp, #-16]!
                    \\ stp     x2,  x3,  [sp, #-16]!
                    \\ stp     x4,  x5,  [sp, #-16]!
                    \\ stp     x6,  x7,  [sp, #-16]!
                    //
                    // Save FP/SIMD argument registers (q0–q7, 16 bytes each)
                    \\ stp     q0,  q1,  [sp, #-32]!
                    \\ stp     q2,  q3,  [sp, #-32]!
                    \\ stp     q4,  q5,  [sp, #-32]!
                    \\ stp     q6,  q7,  [sp, #-32]!
                    //
                    // Call resolver — patches ptr, returns resolved address in x0
                    \\ bl      %[resolve]
                    //
                    // Save resolved address in scratch register
                    \\ mov     x16, x0
                    //
                    // Restore FP/SIMD argument registers
                    \\ ldp     q6,  q7,  [sp], #32
                    \\ ldp     q4,  q5,  [sp], #32
                    \\ ldp     q2,  q3,  [sp], #32
                    \\ ldp     q0,  q1,  [sp], #32
                    //
                    // Restore integer argument registers
                    \\ ldp     x6,  x7,  [sp], #16
                    \\ ldp     x4,  x5,  [sp], #16
                    \\ ldp     x2,  x3,  [sp], #16
                    \\ ldp     x0,  x1,  [sp], #16
                    //
                    // Restore frame pointer + link register
                    \\ ldp     x29, x30, [sp], #16
                    //
                    // Tail-jump to resolved function
                    \\ br      x16
                    :
                    : [resolve] "X" (&resolveAndPatch),
                ),

                else => @compileError(
                    "solazy: asm trampoline not implemented for " ++ @tagName(builtin.cpu.arch) ++
                        ". Build with the self-hosted backend or add a trampoline for this arch.",
                ),
            }
        }
    };
}

// ############################################################################
//
//  Self-hosted backend fallback: comptime-generated stubs
//
//  When the LLVM assembler isn't available, we generate a stub function
//  with the exact signature of the target by switching on parameter count.
//  The stub resolves, patches ptr, and tail-calls via @call.
//
//  Same self-patching semantics: after first call, ptr IS the real function.
//
// ############################################################################

fn FallbackSlot(
    comptime lib_name: [*:0]const u8,
    comptime sym_name: [*:0]const u8,
    comptime FnPtr: type,
) type {
    const fn_info = @typeInfo(@typeInfo(FnPtr).pointer.child).@"fn";
    const params = fn_info.params;
    const P = extractParamTypes(params);
    const R = fn_info.return_type.?;
    const cc = fn_info.calling_convention;

    return switch (params.len) {
        0 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{}),
        1 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{P[0]}),
        2 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1] }),
        3 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2] }),
        4 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3] }),
        5 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4] }),
        6 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5] }),
        7 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6] }),
        8 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6], P[7] }),
        9 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8] }),
        10 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8], P[9] }),
        11 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8], P[9], P[10] }),
        12 => FbSlot(lib_name, sym_name, FnPtr, cc, R, .{ P[0], P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8], P[9], P[10], P[11] }),
        else => unreachable,
    };
}

fn extractParamTypes(comptime params: anytype) [12]type {
    var result: [12]type = .{void} ** 12;
    for (0..params.len) |i| {
        result[i] = params[i].type orelse
            @compileError("solazy: generic parameter types not supported");
    }
    return result;
}

// A single generic FbSlot dispatches on the tuple length to produce
// the right stub signature. This avoids 13 separate named functions.
fn FbSlot(
    comptime lib: [*:0]const u8,
    comptime sym: [*:0]const u8,
    comptime FnPtr: type,
    comptime cc: std.builtin.CallingConvention,
    comptime R: type,
    comptime P: anytype,
) type {
    return switch (P.len) {
        0 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub() callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{});
            }
        },
        1 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{a0});
            }
        },
        2 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1 });
            }
        },
        3 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2 });
            }
        },
        4 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3 });
            }
        },
        5 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4 });
            }
        },
        6 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5 });
            }
        },
        7 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6 });
            }
        },
        8 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6], a7: P[7]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6, a7 });
            }
        },
        9 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6], a7: P[7], a8: P[8]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8 });
            }
        },
        10 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6], a7: P[7], a8: P[8], a9: P[9]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9 });
            }
        },
        11 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6], a7: P[7], a8: P[8], a9: P[9], a10: P[10]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 });
            }
        },
        12 => struct {
            pub var ptr: FnPtr = @ptrCast(&stub);
            fn stub(a0: P[0], a1: P[1], a2: P[2], a3: P[3], a4: P[4], a5: P[5], a6: P[6], a7: P[7], a8: P[8], a9: P[9], a10: P[10], a11: P[11]) callconv(cc) R {
                ptr = resolveOrPanic(lib, sym, FnPtr);
                return @call(.auto, ptr, .{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 });
            }
        },
        else => unreachable,
    };
}

const builtin = @import("builtin");
const std = @import("std");
