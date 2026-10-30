//! **THE PLAYGROUND'S WASM, HELD TO THE JUDGE'S FROZEN ANSWERS** (`zig build
//! test`): the built folder's md.wasm, run in node through the page's own
//! door (md_wasm.js, by check.mjs), asked for known cases in each mode, and
//! its html, work units and hostility compared byte for byte with what the
//! judge froze. **The browser's renderer must be the judge's.** The cases:
//! every canned example, a table, a list and a fence with empty lines
//! inside, and a hostile shape (whose html is frozen as its hash). Then the
//! page itself, run on a stand-in DOM (page_check.mjs).
//!
//! **A MODE THE CASES CANNOT TELL APART IS A FAIL**: for each two modes
//! some case's frozen html differs, so a wasm rendering the wrong mode is
//! red, never green by coincidence.
//!
//! Like the judge it prints ids and counts, never a case's text.
//!
//!   playground_check <node> <playground/check.mjs> <the built folder>

const std = @import("std");
const Io = std.Io;
const judge = @import("judge");
const data_path = @import("judge_paths").data;

const Mode = enum { chat, trusted, reflow };
const modes = std.enums.values(Mode);

const Pick = struct { corpus: []const u8, id: []const u8 };

/// The committed cases: each corpus's file, less `.jsonl`.
const picks = [_]Pick{
    .{ .corpus = "spec_tables", .id = "gfm/198" }, // a table
    .{ .corpus = "spec_agree", .id = "cm/326" }, // a list, an empty line inside
    .{ .corpus = "spec_agree", .id = "cm/129" }, // a fence, an empty line inside
    .{ .corpus = "spec_agree", .id = "cm/324" }, // a fence in a list item, and one
};

/// A generated hostile shape: its html is frozen as hashes.
const hostile_id = "hostile/tbl-ragged/200";

/// The example whose render time is reported, and how many runs it takes.
const timed_id = "blocks";
const timed_runs = 50;

const Case = struct { id: []const u8, md: []const u8, frozen: judge.Frozen };

/// What the wasm answered for one request (check.mjs's line).
const Got = struct { html: []const u8, work_units: u64, hostile: []const u8, ms: f64 };

/// The frozen html of `mode`: its text, or (a generated case's) its hash.
fn frozenHtml(f: judge.Frozen, mode: Mode) struct { text: ?[]const u8, hash: ?[]const u8 } {
    return switch (mode) {
        .chat => .{ .text = f.html, .hash = f.html_hash },
        .trusted => .{ .text = f.trusted, .hash = f.trusted_hash },
        .reflow => .{ .text = f.trusted_reflow, .hash = f.trusted_reflow_hash },
    };
}

var failed: usize = 0;

fn check(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (ok) return;
    failed += 1;
    std.debug.print("PLAYFAIL\t" ++ fmt ++ "\n", args);
}

/// `argv` run with `input` on its stdin: its exit and its stdout.
fn runNode(io: Io, a: std.mem.Allocator, argv: []const []const u8, input: []const u8) !struct { ok: bool, out: []const u8 } {
    var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .pipe, .stdout = .pipe, .stderr = .inherit });
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

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) {
        std.debug.print("usage: playground_check <node> <check.mjs> <the built folder>\n", .{});
        std.process.exit(2);
    }
    const node, const script, const site = .{ args[1], args[2], args[3] };
    const data = try Io.Dir.cwd().openDir(io, data_path, .{});
    defer data.close(io);

    // The cases: every canned example, the picks, the hostile shape.
    var cases: std.ArrayList(Case) = .empty;
    const exs = try judge.readCorpus(io, data, a, "examples.jsonl", "user-uploads");
    check(exs.len >= 5, "examples\tonly {d} canned examples", .{exs.len});
    for (exs) |e| try cases.append(a, try findCase(io, data, a, "examples", e.id));
    for (picks) |p| try cases.append(a, try findCase(io, data, a, p.corpus, p.id));
    const hostile = for (try judge.hostileCases(a)) |c| {
        if (std.mem.eql(u8, c.id, hostile_id)) break c;
    } else return error.NoHostileShape;
    const hbook = (try judge.readAnswers(io, data, a, "hostile.answers.jsonl")).?;
    const hf = hbook.get(hostile_id) orelse return error.NoHostileAnswers;
    check(hf.hostile.len > 0, "{s}\tthe hostile shape is renderable", .{hostile_id});
    try cases.append(a, .{ .id = hostile_id, .md = hostile.md, .frozen = hf });

    // Each two modes told apart by some case.
    for (modes, 0..) |m1, i| for (modes[i + 1 ..]) |m2| {
        var apart = false;
        for (cases.items) |c| {
            const x, const y = .{ frozenHtml(c.frozen, m1), frozenHtml(c.frozen, m2) };
            apart = apart or !std.mem.eql(u8, x.text orelse x.hash.?, y.text orelse y.hash.?);
        }
        check(apart, "modes\tno case tells {t} from {t}", .{ m1, m2 });
    };

    // Every case in every mode, in one run of node; then the timed example.
    var input: std.ArrayList(u8) = .empty;
    for (modes) |mode| for (cases.items) |c|
        try input.print(a, "{{\"md\":{f},\"mode\":\"{t}\"}}\n", .{ std.json.fmt(c.md, .{}), mode });
    const timed = (try findCase(io, data, a, "examples", timed_id)).md;
    for (0..timed_runs) |_| try input.print(a, "{{\"md\":{f},\"mode\":\"chat\"}}\n", .{std.json.fmt(timed, .{})});

    const got = try runNode(io, a, &.{ node, script, site }, input.items);
    check(got.ok, "node\tcheck.mjs failed", .{});
    var answers: std.ArrayList(Got) = .empty;
    var lines = std.mem.splitScalar(u8, got.out, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try answers.append(a, try std.json.parseFromSliceLeaky(Got, a, line, .{}));
    }
    const want_n = modes.len * cases.items.len + timed_runs;
    if (answers.items.len != want_n) {
        check(false, "node\t{d} answers for {d} requests", .{ answers.items.len, want_n });
        std.process.exit(1);
    }

    var k: usize = 0;
    for (modes) |mode| for (cases.items) |c| {
        const g = answers.items[k];
        k += 1;
        const f = c.frozen;
        const want = frozenHtml(f, mode);
        const html_ok = if (want.text) |t| std.mem.eql(u8, g.html, t) else std.mem.eql(u8, try judge.textHash(a, g.html), want.hash.?);
        check(html_ok, "{t}\t{s}\tits html is not the frozen one", .{ mode, c.id });
        check(g.work_units == f.work_units, "{t}\t{s}\tits work units are {d}, frozen {d}", .{ mode, c.id, g.work_units, f.work_units });
        check(std.mem.eql(u8, g.hostile, f.hostile), "{t}\t{s}\tits hostility is not the frozen one", .{ mode, c.id });
    };
    // The timed runs: their median (the first ones warm the JIT up).
    const ms = try a.alloc(f64, timed_runs);
    for (answers.items[k..], ms) |g, *m| m.* = g.ms;
    std.mem.sort(f64, ms, {}, std.sort.asc(f64));

    // The page on a stand-in DOM, from the same folder.
    const page_script = try std.fs.path.join(a, &.{ std.fs.path.dirname(script).?, "page_check.mjs" });
    const page = try runNode(io, a, &.{ node, page_script, site }, "");
    check(page.ok, "page\tpage_check.mjs failed", .{});
    if (std.mem.indexOf(u8, page.out, "== page:")) |at| std.debug.print("{s}", .{page.out[at..]});

    std.debug.print("== playground: {d} cases ({d} canned examples) in {d} modes through md.wasm in node, {d} fail; `{s}` renders in {d:.2} ms (the median of {d} runs)\n", .{ cases.items.len, exs.len, modes.len, failed, timed_id, ms[ms.len / 2], timed_runs });
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
    std.debug.print("PLAYFAIL\t{s}\tno such case in {s}\n", .{ id, corpus });
    return error.NoCase;
}
