//! **THE JUDGE'S SIDE OF THE ROC** (judge/answers.roc on judge/platform/):
//! `answers` hands a message to the package and copies out its five
//! answers, and the runtime the archive needs (`roc_alloc`, `roc_realloc`,
//! `roc_dealloc`, `roc_crashed`, `roc_dbg`, `roc_expect_failed`). The layouts
//! are roc-webbox's src/roc_abi.zig's, which Roc nightly-2026-10-09 (the
//! roc-version pin) lays out so.
//!
//! **ONE CALL AT A TIME, IN ONE ARENA**: the judge is single-threaded, so
//! every allocation of a call is in one arena, dropped as the call ends;
//! `roc_dealloc` frees nothing.

const std = @import("std");

/// A Roc `List(U8)`: pointer, length, then the capacity (shifted), the
/// bytes after a refcount word.
const RocBytes = extern struct {
    ptr: ?[*]u8,
    length: usize,
    capacity_or_alloc_ptr: usize,

    fn slice(b: *const RocBytes) []const u8 {
        const p = b.ptr orelse return "";
        return p[0..b.length];
    }

    /// A new list holding `bytes`, in the call's arena.
    fn from(bytes: []const u8) RocBytes {
        if (bytes.len == 0) return .{ .ptr = null, .length = 0, .capacity_or_alloc_ptr = 0 };
        const w = @sizeOf(usize);
        const base = allocate(w + bytes.len, w);
        std.mem.writeInt(usize, base[0..w], 1, .little);
        const data = base + w;
        @memcpy(data[0..bytes.len], bytes);
        return .{ .ptr = data, .length = bytes.len, .capacity_or_alloc_ptr = bytes.len << 1 };
    }
};

/// A Roc `List(List(U8))`.
const RocBytesList = extern struct {
    ptr: ?[*]RocBytes,
    length: usize,
    capacity_or_alloc_ptr: usize,

    fn slice(l: *const RocBytesList) []const RocBytes {
        const p = l.ptr orelse return &.{};
        return p[0..l.length];
    }
};

/// The five answers, in judge/answers.roc's order.
pub const Part = enum { render, work_units, hostile_reason, trusted, trusted_reflow };

extern fn roc_judge_answers(md: RocBytes, uploads: RocBytes) callconv(.c) RocBytesList;

var arena: ?std.heap.ArenaAllocator = null;

/// The arena, from `base`, once, before the first call.
pub fn use(base: std.mem.Allocator) void {
    arena = .init(base);
}

pub fn deinit() void {
    if (arena) |*a| a.deinit();
    arena = null;
}

/// The package's answers for `md`, each copied into `alloc`, the call's
/// memory dropped. `uploads` names the host's rule for which paths are its
/// uploads (judge/answers.roc's `uploads_of`: `user-uploads`, `same-origin`
/// or `old-chat`).
pub fn answers(alloc: std.mem.Allocator, md: []const u8, uploads: []const u8) ![][]u8 {
    defer _ = arena.?.reset(.retain_capacity);
    const got = roc_judge_answers(.from(md), .from(uploads));
    const items = got.slice();
    const out = try alloc.alloc([]u8, items.len);
    for (items, 0..) |*it, k| out[k] = try alloc.dupe(u8, it.slice());
    return out;
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
    std.debug.assert(alignment <= header);
    const got = arena.?.allocator().alignedAlloc(u8, .fromByteUnits(header), header + len) catch
        std.debug.panic("roc_alloc: out of memory ({d} bytes)", .{len});
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

/// **A ROC CRASH STOPS THE JUDGE**, saying Roc's message (the package's
/// own words, never a case's text): a case the package cannot answer is a
/// bug to fix, not a verdict to tally.
fn roc_crashed(bytes: [*]const u8, len: usize) callconv(.c) void {
    std.debug.panic("roc crashed: {s}", .{bytes[0..len]});
}

fn roc_dbg() callconv(.c) void {
    std.debug.panic("roc: a `dbg` was reached", .{});
}

fn roc_expect_failed() callconv(.c) void {
    std.debug.panic("roc: an inline `expect` failed", .{});
}
