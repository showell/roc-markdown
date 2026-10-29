//! **THE PLAYGROUND'S SIDE OF THE ROC** (playground/answer.roc on
//! playground/platform/), compiled to a wasm32-freestanding object that the
//! pinned Roc links into the page's wasm. The page's door is four exports:
//!
//!   input(len) -> ptr     a fresh list of `len` bytes; the page writes the
//!                         message there. Everything of the last call is
//!                         dropped first.
//!   answer(len, mode)     the package's answers for those bytes in that mode
//!                         (0 chat, 1 trusted, 2 reflow); their count.
//!   partPtr(k), partLen(k)  answer k's bytes, until the next `input`.
//!
//! **ONE CALL AT A TIME, IN ONE ARENA**, as the judge's host
//! (judge/roc_host.zig) does it: every allocation of a call is in one arena,
//! dropped by the next `input`, so `roc_dealloc` frees nothing. The list
//! layouts are the judge's, which the roc-version pin lays out so.

const std = @import("std");

pub const panic = std.debug.FullPanic(panicImpl);
fn panicImpl(_: []const u8, _: ?usize) noreturn {
    @trap();
}

/// A Roc `List(U8)`: pointer, length, then the capacity (shifted), the
/// bytes after a refcount word.
const RocBytes = extern struct {
    ptr: ?[*]u8,
    length: usize,
    capacity_or_alloc_ptr: usize,
};

/// A Roc `List(List(U8))`.
const RocBytesList = extern struct {
    ptr: ?[*]RocBytes,
    length: usize,
    capacity_or_alloc_ptr: usize,
};

extern fn roc_play_answer(md: RocBytes, mode: u8) callconv(.c) RocBytesList;

var arena: std.heap.ArenaAllocator = .init(std.heap.wasm_allocator);

/// The message the page is writing, then the answers it reads.
var pending: RocBytes = .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
var answers: RocBytesList = .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };

pub export fn input(len: u32) u32 {
    _ = arena.reset(.retain_capacity);
    answers = .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
    if (len == 0) {
        pending = .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
        return 0;
    }
    const w = @sizeOf(usize);
    const base = allocate(w + len, w);
    std.mem.writeInt(usize, base[0..w], 1, .little);
    pending = .{ .ptr = base + w, .length = len, .capacity_or_alloc_ptr = @as(usize, len) << 1 };
    return @intCast(@intFromPtr(pending.ptr.?));
}

/// **THE LENGTH IS SAID TWICE**, by `input` and here, and must agree: a
/// page that wrote another message than it allocated is a bug, never a
/// render of half of one.
pub export fn answer(len: u32, mode: u32) u32 {
    if (len != pending.length or mode > 2) @trap();
    answers = roc_play_answer(pending, @intCast(mode));
    pending = .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
    return @intCast(answers.length);
}

fn part(k: u32) RocBytes {
    if (k >= answers.length) @trap();
    return answers.ptr.?[k];
}

pub export fn partPtr(k: u32) u32 {
    const p = part(k).ptr orelse return 0;
    return @intCast(@intFromPtr(p));
}

pub export fn partLen(k: u32) u32 {
    return @intCast(part(k).length);
}

// ── the runtime ─────────────────────────────────────────────────────────────

comptime {
    @export(&roc_alloc, .{ .name = "roc_alloc" });
    @export(&roc_realloc, .{ .name = "roc_realloc" });
    @export(&roc_dealloc, .{ .name = "roc_dealloc" });
    @export(&roc_crashed, .{ .name = "roc_crashed" });
    @export(&roc_dbg, .{ .name = "roc_dbg" });
    @export(&roc_expect_failed, .{ .name = "roc_expect_failed" });
}

/// Each allocation's size, just before what Roc is given, so `roc_realloc`
/// knows how much to copy. 16 bytes: Roc asks for at most 16's alignment.
const header = 16;

fn allocate(len: usize, alignment: usize) [*]u8 {
    if (alignment > header) @trap();
    const got = arena.allocator().alignedAlloc(u8, .fromByteUnits(header), header + len) catch @trap();
    std.mem.writeInt(usize, got[0..@sizeOf(usize)], len, .little);
    return got.ptr + header;
}

fn roc_alloc(len: usize, alignment: usize) callconv(.c) *anyopaque {
    return allocate(len, alignment);
}

fn roc_realloc(ptr: *anyopaque, len: usize, alignment: usize) callconv(.c) *anyopaque {
    const old: [*]u8 = @ptrCast(ptr);
    const was = std.mem.readInt(usize, (old - header)[0..@sizeOf(usize)], .little);
    const new = allocate(len, alignment);
    @memcpy(new[0..@min(was, len)], old[0..@min(was, len)]);
    return new;
}

fn roc_dealloc(ptr: *anyopaque, alignment: usize) callconv(.c) void {
    _ = ptr;
    _ = alignment;
}

/// **A ROC CRASH TRAPS**: the page sees the wasm's `unreachable` and says
/// the renderer failed, never a stale or empty preview.
fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    _ = bytes;
    _ = len;
    @trap();
}

fn roc_dbg(bytes: [*]const u8, len: usize) callconv(.c) void {
    _ = bytes;
    _ = len;
    @trap();
}

fn roc_expect_failed(bytes: [*]const u8, len: usize) callconv(.c) void {
    _ = bytes;
    _ = len;
    @trap();
}
