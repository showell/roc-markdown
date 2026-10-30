//! **THE REPL, PIPED, HELD TO THE JUDGE'S FROZEN ANSWERS** (`zig build
//! test`): known cases typed into `zig build repl`'s program, as a script
//! would pipe them, in each mode, and its output compared byte for byte with
//! what the frozen answers say it must print. The cases: a table, a list
//! and a fence with empty lines inside, every canned example, and a hostile
//! shape (whose html is frozen as its hash). The canned examples must also
//! be renderable, and `:ex` must print each one's source and answer.
//!
//! **A MODE THE CASES CANNOT TELL APART IS A FAIL**: for each two modes
//! some case's frozen html differs, so a REPL showing the wrong render is
//! red, never green by coincidence.
//!
//! Like the judge it prints ids and counts, never a case's text.
//!
//!   repl_check <the repl program>

const std = @import("std");
const Io = std.Io;
const judge = @import("judge.zig");
const repl = @import("repl.zig");
const data_path = @import("judge_paths").data;

const Pick = struct { corpus: []const u8, id: []const u8 };

/// The committed cases typed in: each corpus's file, less `.jsonl`.
const picks = [_]Pick{
    .{ .corpus = "spec_tables", .id = "gfm/198" }, // a table
    .{ .corpus = "spec_agree", .id = "cm/326" }, // a list, an empty line inside
    .{ .corpus = "spec_agree", .id = "cm/129" }, // a fence, an empty line inside
    .{ .corpus = "spec_agree", .id = "cm/324" }, // a fence in a list item, and one
};

/// A generated hostile shape: its html is frozen as hashes.
const hostile_id = "hostile/tbl-ragged/200";

const modes = std.enums.values(repl.Mode);

/// The frozen html of `mode`: its text, or (a generated case's) its hash.
fn frozenHtml(f: judge.Frozen, mode: repl.Mode) union(enum) { text: []const u8, hash: []const u8 } {
    const text, const hash = switch (mode) {
        .chat => .{ f.html, f.html_hash },
        .trusted => .{ f.trusted, f.trusted_hash },
        .reflow => .{ f.trusted_reflow, f.trusted_reflow_hash },
    };
    if (text) |t| return .{ .text = t };
    return .{ .hash = hash.? };
}

/// `md` as typed at the REPL: its lines, then one empty line; or, when it
/// has empty lines inside, an empty line first and two after.
fn typed(a: std.mem.Allocator, id: []const u8, md: []const u8) ![]const u8 {
    const ok = md.len > 0 and md[md.len - 1] == '\n' and md[0] != '\n' and md[0] != ':' and
        std.mem.indexOf(u8, md, "\n\n\n") == null and !std.mem.endsWith(u8, md, "\n\n");
    if (!ok) {
        std.debug.print("REPLFAIL\t{s}\tits text cannot be typed as one block\n", .{id});
        return error.Untypable;
    }
    if (std.mem.indexOf(u8, md, "\n\n") == null) return std.fmt.allocPrint(a, "{s}\n", .{md});
    return std.fmt.allocPrint(a, "\n{s}\n\n", .{md});
}

/// The REPL run on `input`: its exit and its stdout.
fn runRepl(io: Io, a: std.mem.Allocator, exe: []const u8, input: []const u8) !struct { ok: bool, out: []const u8 } {
    var child = try std.process.spawn(io, .{ .argv = &.{exe}, .stdin = .pipe, .stdout = .pipe, .stderr = .ignore });
    defer child.kill(io);
    try child.stdin.?.writeStreamingAll(io, input);
    child.stdin.?.close(io);
    child.stdin = null;
    var buf: [64 * 1024]u8 = undefined;
    var r = child.stdout.?.readerStreaming(io, &buf);
    const out = try r.interface.allocRemaining(a, .unlimited);
    const term = try child.wait(io);
    return .{ .ok = term.success(), .out = out };
}

/// What `writeBlock` must print for a case whose html is frozen as text.
fn expected(a: std.mem.Allocator, html: []const u8, f: judge.Frozen) ![]const u8 {
    var w: Io.Writer.Allocating = .init(a);
    try repl.writeBlock(&w.writer, html, try std.fmt.allocPrint(a, "{d}", .{f.work_units}), f.hostile);
    return w.written();
}

var failed: usize = 0;

fn check(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (ok) return;
    failed += 1;
    std.debug.print("REPLFAIL\t" ++ fmt ++ "\n", args);
}

const Case = struct { id: []const u8, md: []const u8, frozen: judge.Frozen };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) {
        std.debug.print("usage: repl_check <the repl program>\n", .{});
        std.process.exit(2);
    }
    const exe = args[1];
    const data = try Io.Dir.cwd().openDir(io, data_path, .{});
    defer data.close(io);

    // The text cases: the picks, then every canned example.
    var cases: std.ArrayList(Case) = .empty;
    for (picks) |p| try cases.append(a, try findCase(io, data, a, p.corpus, p.id));
    const exs = try repl.examples(a);
    for (exs) |e| try cases.append(a, try findCase(io, data, a, "examples", e.id));
    for (exs) |e| check(e.caption.len > 0, "{s}\tan example with no caption", .{e.id});
    check(exs.len >= 5, "examples\tonly {d} canned examples", .{exs.len});

    // The hostile shape, generated as the judge generates it.
    const hostile = for (try judge.hostileCases(a)) |c| {
        if (std.mem.eql(u8, c.id, hostile_id)) break c;
    } else return error.NoHostileShape;
    const hbook = (try judge.readAnswers(io, data, a, "hostile.answers.jsonl")).?;
    const hf = hbook.get(hostile_id).?;
    check(hf.hostile.len > 0, "{s}\tthe hostile shape is renderable", .{hostile_id});

    // Each two modes told apart by some case.
    for (modes, 0..) |m1, i| for (modes[i + 1 ..]) |m2| {
        var apart = false;
        for (cases.items) |c| apart = apart or !std.mem.eql(u8, frozenHtml(c.frozen, m1).text, frozenHtml(c.frozen, m2).text);
        apart = apart or !std.mem.eql(u8, frozenHtml(hf, m1).hash, frozenHtml(hf, m2).hash);
        check(apart, "modes\tno case tells {t} from {t}", .{ m1, m2 });
    };

    // The examples: renderable.
    for (exs, cases.items[picks.len..]) |e, c| check(c.frozen.hostile.len == 0, "{s}\ta canned example is hostile", .{e.id});

    var runs: usize = 0;
    for (modes) |mode| {
        // Every text case in one run, so the blocks are also kept apart.
        var input: std.ArrayList(u8) = .empty;
        var want: std.ArrayList(u8) = .empty;
        try input.print(a, ":mode {t}\n", .{mode});
        for (cases.items) |c| {
            try input.appendSlice(a, try typed(a, c.id, c.md));
            try want.appendSlice(a, try expected(a, frozenHtml(c.frozen, mode).text, c.frozen));
        }
        const got = try runRepl(io, a, exe, input.items);
        runs += 1;
        check(got.ok, "{t}\tthe REPL failed", .{mode});
        if (!std.mem.eql(u8, got.out, want.items)) {
            check(false, "{t}\tthe REPL's output is not the frozen answers ({d} bytes, want {d})", .{ mode, got.out.len, want.items.len });
            // Which case first parts ways: the shortest prefix that differs.
            var at: usize = 0;
            for (cases.items) |c| {
                const w = try expected(a, frozenHtml(c.frozen, mode).text, c.frozen);
                if (at + w.len > got.out.len or !std.mem.eql(u8, got.out[at .. at + w.len], w)) {
                    std.debug.print("FAILID\trepl/{t}\t{s}\n", .{ mode, c.id });
                    break;
                }
                at += w.len;
            }
        }

        // The hostile shape: its html by hash, its units and verdict whole.
        const h = try runRepl(io, a, exe, try std.fmt.allocPrint(a, ":mode {t}\n{s}", .{ mode, try typed(a, hostile_id, hostile.md) }));
        runs += 1;
        const tail = try expected(a, "", hf);
        const ends = std.mem.endsWith(u8, h.out, tail);
        check(h.ok and ends, "{t}\t{s}: the REPL's units or verdict are not the frozen ones", .{ mode, hostile_id });
        if (ends) {
            const html = h.out[0 .. h.out.len - tail.len];
            check(std.mem.eql(u8, try judge.textHash(a, html), frozenHtml(hf, mode).hash), "{t}\t{s}: the REPL's html is not the frozen one", .{ mode, hostile_id });
        }

        // `:ex`: each example's source, then its answer.
        for (exs, cases.items[picks.len..]) |e, c| {
            const x = try runRepl(io, a, exe, try std.fmt.allocPrint(a, ":mode {t}\n:ex {s}\n", .{ mode, e.id }));
            runs += 1;
            check(x.ok and std.mem.indexOf(u8, x.out, e.md) != null and std.mem.indexOf(u8, x.out, e.caption) != null and
                std.mem.endsWith(u8, x.out, try expected(a, frozenHtml(c.frozen, mode).text, c.frozen)), "{t}\t:ex {s}: not its source and its frozen answer", .{ mode, e.id });
        }
    }

    // Piped, a command that fails stops the run.
    const bad = try runRepl(io, a, exe, ":nope\n**hi**\n\n");
    runs += 1;
    check(!bad.ok and bad.out.len == 0, "an unknown command, piped, did not stop the run", .{});
    // Piped, end of input ends the last block.
    const eof = try runRepl(io, a, exe, ":mode chat\n**hi**");
    runs += 1;
    check(eof.ok and std.mem.startsWith(u8, eof.out, "<p><strong>hi</strong></p>\n"), "end of input did not end the last block", .{});

    std.debug.print("== repl: {d} cases ({d} canned examples) in {d} modes, {d} runs of the REPL, {d} fail\n", .{ cases.items.len + 1, exs.len, modes.len, runs, failed });
    if (failed > 0) std.process.exit(1);
}

/// A case of `corpus` and its frozen answers, by id.
fn findCase(io: Io, data: Io.Dir, a: std.mem.Allocator, corpus: []const u8, id: []const u8) !Case {
    const cs = try judge.readCorpus(io, data, a, try std.fmt.allocPrint(a, "{s}.jsonl", .{corpus}), "user-uploads");
    const book = (try judge.readAnswers(io, data, a, try std.fmt.allocPrint(a, "{s}.answers.jsonl", .{corpus}))) orelse return error.NoAnswers;
    for (cs) |c| if (std.mem.eql(u8, c.id, id)) {
        const f = book.get(id) orelse return error.NoAnswers;
        return .{ .id = id, .md = c.md, .frozen = f };
    };
    std.debug.print("REPLFAIL\t{s}\tno such case in {s}\n", .{ id, corpus });
    return error.NoCase;
}
