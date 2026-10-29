//! **THE PACKAGE'S MARKDOWN, HELD TO ITS FROZEN ANSWERS** (roc-markdown's
//! judge): every case of every corpus is rendered by the package (through
//! judge/answers.roc) and must give the five answers recorded for it:
//! `render`'s html, the work units, the hostility words, `render_trusted`'s
//! html and `render_trusted_reflow`'s html. A case's answers move only by an
//! explicit re-freeze, which names each case it moves.
//!
//! **IT PRINTS ONLY COUNTS AND CASE IDS, NEVER A CASE'S TEXT**: it is run
//! over a private corpus of real messages (`--also`), so nothing a message
//! holds reaches its output. A failing case is named by its id and the
//! answers that differ.
//!
//!   zig build test     (part of it) the corpora judge/data/corpora.txt
//!       lists, and the hostile shapes generated here, every case held to
//!       its answers: a case with none, a case whose text is not the text
//!       frozen, and an answer whose case is gone each fail too. Each
//!       corpus's pass count is also held to judge/data/ratchet.txt, which
//!       may only rise, so a corpus that loses cases is caught. The spec's
//!       corpora (spec_agree, CommonMark's and GFM's examples, and
//!       spec_tables, GFM's tables) are held to the spec's html too, less
//!       the divergences judge/data/spec_diverge.txt lists (specCheck).
//!   zig build judge -- --also PATH       one more corpus, not ratcheted
//!   zig build judge -- --refreeze LABEL  that corpus's answers recorded
//!                             again (LABEL: its file's name less `.jsonl`,
//!                             or `hostile`), each case whose answers
//!                             changed, was added or was dropped named; the
//!                             one way a case's answers move. Given again,
//!                             another.
//!   zig build judge -- --raise           the ratchet rewritten to today's counts
//!   zig build judge -- --time            each corpus's render time
//!   zig build judge -- --data DIR        a copy of judge/data in its place
//!                             (tools/verify.shale's planted faults)
//!
//! **ITS DATA IS FOUND FROM THE BUILD** (`judge_data`, judge/data/'s path),
//! never from the working directory; an `--also` path is the caller's, and
//! its answers are beside it.
//!
//! A corpus is jsonl, one `{"id", "md"}` a line (other fields, such as the
//! spec corpus's `html`, are ignored by the frozen check); an id twice is
//! refused. **ITS ANSWERS ARE BESIDE IT**: `X.jsonl`'s are `X.answers.jsonl`,
//! one `{"id", "md_hash", "html", "work_units", "hostile", "trusted",
//! "trusted_reflow"}` a case, in the corpus's order (`md_hash` the Wyhash of
//! the case's text); the hostile shapes' are judge/data/hostile.answers.jsonl.
//! **A GENERATED CORPUS'S HTML IS FROZEN AS ITS HASH** (the hostile shapes':
//! `html_hash`, `trusted_hash`, `trusted_reflow_hash`, each the Wyhash of
//! the html, in place of the text): their html is megabytes of one unit
//! repeated, and their text is regenerated from the shapes, so a re-freeze
//! names a moved case and the shape and size say what it was. A real
//! corpus keeps its full html, so a re-freeze's diff shows what moved. A
//! corpus or an answers file that cannot be read stops the run: a judge
//! that skipped its bulk would pass having checked almost nothing.

const std = @import("std");
const Io = std.Io;
const roc = @import("roc_host.zig");
const data_path = @import("judge_paths").data;

const corpora_list = "corpora.txt";
const ratchet_path = "ratchet.txt";
const hostile_answers_path = "hostile.answers.jsonl";
/// The spec's corpora: CommonMark's and GFM's examples, and GFM's table
/// examples (QUEUE 311), checked as one against spec_diverge.txt.
const spec_labels = [_][]const u8{ "spec_agree", "spec_tables" };
const spec_diverge_path = "spec_diverge.txt";

const Part = roc.Part;
const part_count = std.enums.values(Part).len;
const Answers = [part_count][]const u8;

/// A case; `html`, where a corpus has it, is another renderer's answer (the
/// spec's, for the spec check), never the frozen one.
pub const Case = struct { id: []const u8, md: []const u8, html: ?[]const u8 = null };

/// A case's answers as its corpus's answers file records them: each html
/// as its text, or (a generated corpus's) as its hash, never both.
pub const Frozen = struct {
    id: []const u8,
    md_hash: []const u8,
    html: ?[]const u8 = null,
    html_hash: ?[]const u8 = null,
    work_units: u64,
    hostile: []const u8,
    trusted: ?[]const u8 = null,
    trusted_hash: ?[]const u8 = null,
    trusted_reflow: ?[]const u8 = null,
    trusted_reflow_hash: ?[]const u8 = null,
};

/// A frozen answer: its text, or the hash of its text.
const Want = union(enum) { text: []const u8, hash: []const u8 };
const Wants = [part_count]Want;

/// How a corpus's html is frozen: whole (a real corpus), or hashed (a
/// generated one).
const Keep = enum { whole, hashed };

/// A corpus's answers, by case id.
pub const Book = std.StringHashMapUnmanaged(Frozen);

/// A case's verdict: the parts that differ, a package that gave the wrong
/// number of answers, or a case the answers do not cover. (A Roc crash
/// stops the judge: roc_host.zig.)
const Verdict = union(enum) {
    same,
    differ: [part_count]bool,
    roc_answered: usize,
    /// No answers recorded for the case: a case added without a re-freeze.
    unfrozen,
    /// The case's text is not the text its answers were recorded for.
    text_changed,
};

/// The package's five answers for `md`, in `a`, or how many it gave.
const RocResult = union(enum) { answers: Answers, answered: usize };

fn rocAnswers(a: std.mem.Allocator, md: []const u8) !RocResult {
    const got = try roc.answers(a, md);
    if (got.len != part_count) return .{ .answered = got.len };
    var out: Answers = undefined;
    for (got, 0..) |r, k| out[k] = r;
    return .{ .answers = out };
}

fn compare(a: std.mem.Allocator, want: Wants, got: Answers) !Verdict {
    var differ: [part_count]bool = @splat(false);
    var any = false;
    for (want, got, 0..) |w, g, k| {
        differ[k] = switch (w) {
            .text => |t| !std.mem.eql(u8, t, g),
            .hash => |h| !std.mem.eql(u8, h, try textHash(a, g)),
        };
        any = any or differ[k];
    }
    return if (any) .{ .differ = differ } else .same;
}

/// The package against the case's recorded answers.
fn judgeFrozen(a: std.mem.Allocator, md: []const u8, frozen: ?Frozen) !Verdict {
    const f = frozen orelse return .unfrozen;
    if (!std.mem.eql(u8, f.md_hash, try textHash(a, md))) return .text_changed;
    const got = switch (try rocAnswers(a, md)) {
        .answers => |g| g,
        .answered => |n| return .{ .roc_answered = n },
    };
    return compare(a, try wantsOf(a, f), got);
}

/// A frozen case's answers, each html its text or its hash.
fn wantsOf(a: std.mem.Allocator, f: Frozen) !Wants {
    return .{
        try wantOf(f.id, "html", f.html, f.html_hash),
        .{ .text = try std.fmt.allocPrint(a, "{d}", .{f.work_units}) },
        .{ .text = f.hostile },
        try wantOf(f.id, "trusted", f.trusted, f.trusted_hash),
        try wantOf(f.id, "trusted_reflow", f.trusted_reflow, f.trusted_reflow_hash),
    };
}

fn wantOf(id: []const u8, part: []const u8, text: ?[]const u8, hash: ?[]const u8) !Want {
    if (text) |t| {
        if (hash == null) return .{ .text = t };
    } else if (hash) |h| return .{ .hash = h };
    std.debug.print("the answers of {s}: its {s} needs its text or its hash, one of the two\n", .{ id, part });
    return error.AnswerTextOrHash;
}

/// A text named by its hash: a case's, so a frozen answer knows its case,
/// and a generated case's html.
pub fn textHash(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{x:0>16}", .{std.hash.Wyhash.hash(0, text)});
}

/// The parts of a `differ`, comma-separated, onto stderr.
fn printParts(d: [part_count]bool) void {
    var first = true;
    for (d, 0..) |bad, k| {
        if (!bad) continue;
        if (!first) std.debug.print(",", .{});
        std.debug.print("{s}", .{@tagName(@as(Part, @fromBackingInt(@intCast(k))))});
        first = false;
    }
}

/// `FAILID`, the corpus, the id and what differed: never the text.
fn printFailure(label: []const u8, id: []const u8, v: Verdict) void {
    std.debug.print("FAILID\t{s}\t{s}\t", .{ label, id });
    switch (v) {
        .same => unreachable,
        .roc_answered => |n| std.debug.print("the package gave {d} answers", .{n}),
        .unfrozen => std.debug.print("no answers recorded (--refreeze {s})", .{label}),
        .text_changed => std.debug.print("its text is not the text frozen (--refreeze {s})", .{label}),
        .differ => |d| printParts(d),
    }
    std.debug.print("\n", .{});
}

/// A corpus's count: cases agreeing, failing, and the hostile ones among
/// all (so a run says how much of the refusal path it reached).
const Tally = struct { pass: usize = 0, fail: usize = 0, hostile: usize = 0 };

/// Every case against its answers in `book`, and every answer whose case is
/// gone (`STALE`, a failure: its corpus lost a case without a re-freeze).
fn judgeFrozenCases(arena: *std.heap.ArenaAllocator, label: []const u8, cases: []const Case, book: *const Book) !Tally {
    var t: Tally = .{};
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(std.heap.page_allocator);
    for (cases) |c| {
        _ = arena.reset(.retain_capacity);
        try seen.put(std.heap.page_allocator, c.id, {});
        const frozen = book.get(c.id);
        if (frozen) |f| {
            if (f.hostile.len > 0) t.hostile += 1;
        }
        const v = try judgeFrozen(arena.allocator(), c.md, frozen);
        if (v == .same) {
            t.pass += 1;
        } else {
            t.fail += 1;
            printFailure(label, c.id, v);
        }
    }
    var it = book.keyIterator();
    while (it.next()) |id| {
        if (seen.contains(id.*)) continue;
        t.fail += 1;
        std.debug.print("STALE\t{s}\t{s}\tan answer whose case is gone (--refreeze {s})\n", .{ label, id.*, label });
    }
    return t;
}

/// The cases of a jsonl corpus, `path` in `dir`, in `a`. An id twice is
/// refused: an answer is found by its case's id.
pub fn readCorpus(io: Io, dir: Io.Dir, a: std.mem.Allocator, path: []const u8) ![]Case {
    const data = dir.readFileAlloc(io, path, a, .unlimited) catch |e| {
        std.debug.print("cannot read the corpus {s}: {s}\n", .{ path, @errorName(e) });
        return e;
    };
    var cases: std.ArrayList(Case) = .empty;
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    var n: usize = 0;
    while (lines.next()) |line| {
        n += 1;
        if (line.len == 0) continue;
        const c = std.json.parseFromSliceLeaky(Case, a, line, .{ .ignore_unknown_fields = true }) catch |e| {
            std.debug.print("{s}:{d}: not a case: {s}\n", .{ path, n, @errorName(e) });
            return e;
        };
        if ((try ids.fetchPut(a, c.id, {})) != null) {
            std.debug.print("{s}:{d}: the id {s} again\n", .{ path, n, c.id });
            return error.CaseIdTwice;
        }
        try cases.append(a, c);
    }
    return cases.items;
}

/// A corpus's answers file, `path` in `dir`, by id, in `a`; null when there
/// is none yet.
pub fn readAnswers(io: Io, dir: Io.Dir, a: std.mem.Allocator, path: []const u8) !?Book {
    const data = dir.readFileAlloc(io, path, a, .unlimited) catch |e| switch (e) {
        error.FileNotFound => return null,
        else => {
            std.debug.print("cannot read the answers {s}: {s}\n", .{ path, @errorName(e) });
            return e;
        },
    };
    var book: Book = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    var n: usize = 0;
    while (lines.next()) |line| {
        n += 1;
        if (line.len == 0) continue;
        const f = std.json.parseFromSliceLeaky(Frozen, a, line, .{}) catch |e| {
            std.debug.print("{s}:{d}: not an answer: {s}\n", .{ path, n, @errorName(e) });
            return e;
        };
        if ((try book.fetchPut(a, f.id, f)) != null) {
            std.debug.print("{s}:{d}: the id {s} again\n", .{ path, n, f.id });
            return error.AnswerIdTwice;
        }
    }
    return book;
}

/// A corpus's label: its file's name without `.jsonl`.
fn labelOf(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    return if (std.mem.endsWith(u8, base, ".jsonl")) base[0 .. base.len - 6] else base;
}

/// Where a corpus's answers are: beside it, `X.jsonl`'s as `X.answers.jsonl`.
fn answersPathOf(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, path, ".jsonl")) path[0 .. path.len - 6] else path;
    return std.fmt.allocPrint(a, "{s}.answers.jsonl", .{stem});
}

// ── the re-freeze ───────────────────────────────────────────────────────────

/// **A CORPUS'S ANSWERS RECORDED AGAIN, FROM THE PACKAGE**: each case's
/// five, written over `path` in `dir`; each case whose answers changed
/// (`REFROZE ... changed: <parts>`), was added or was dropped named against
/// `old`. A case the package cannot answer stops it, nothing written.
/// `keep` says whether the html is written whole or as its hash.
fn refreeze(io: Io, arena: *std.heap.ArenaAllocator, label: []const u8, cases: []const Case, keep: Keep, old: ?Book, dir: Io.Dir, path: []const u8) !Tally {
    const alloc = std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    var t: Tally = .{};
    var added: usize = 0;
    var changed: usize = 0;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(alloc);
    for (cases) |c| {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();
        try seen.put(alloc, c.id, {});
        const got = switch (try rocAnswers(a, c.md)) {
            .answers => |g| g,
            .answered => |n| {
                printFailure(label, c.id, .{ .roc_answered = n });
                return error.RefreezeRocFailed;
            },
        };
        const units = std.fmt.parseInt(u64, got[@backingInt(Part.work_units)], 10) catch {
            std.debug.print("FAILID\t{s}\t{s}\tthe package's work units are not a number\n", .{ label, c.id });
            return error.RefreezeRocFailed;
        };
        const hash = try textHash(a, c.md);
        if (got[@backingInt(Part.hostile_reason)].len > 0) t.hostile += 1;
        t.pass += 1;
        const before = if (old) |b| b.get(c.id) else null;
        if (before) |f| {
            if (!std.mem.eql(u8, f.md_hash, hash)) {
                changed += 1;
                std.debug.print("REFROZE\t{s}\t{s}\tits text changed\n", .{ label, c.id });
            } else switch (try compare(a, try wantsOf(a, f), got)) {
                .same => {},
                .differ => |d| {
                    changed += 1;
                    std.debug.print("REFROZE\t{s}\t{s}\tchanged: ", .{ label, c.id });
                    printParts(d);
                    std.debug.print("\n", .{});
                },
                else => unreachable,
            }
        } else if (old != null) {
            added += 1;
            std.debug.print("REFROZE\t{s}\t{s}\tadded\n", .{ label, c.id });
        }
        const html = got[@backingInt(Part.render)];
        const trusted = got[@backingInt(Part.trusted)];
        const reflow = got[@backingInt(Part.trusted_reflow)];
        switch (keep) {
            .whole => try out.print(alloc, "{{\"id\":{f},\"md_hash\":\"{s}\",\"html\":{f},\"work_units\":{d},\"hostile\":{f},\"trusted\":{f},\"trusted_reflow\":{f}}}\n", .{
                std.json.fmt(c.id, .{}),
                hash,
                std.json.fmt(html, .{}),
                units,
                std.json.fmt(got[@backingInt(Part.hostile_reason)], .{}),
                std.json.fmt(trusted, .{}),
                std.json.fmt(reflow, .{}),
            }),
            .hashed => try out.print(alloc, "{{\"id\":{f},\"md_hash\":\"{s}\",\"html_hash\":\"{s}\",\"work_units\":{d},\"hostile\":{f},\"trusted_hash\":\"{s}\",\"trusted_reflow_hash\":\"{s}\"}}\n", .{
                std.json.fmt(c.id, .{}),
                hash,
                try textHash(a, html),
                units,
                std.json.fmt(got[@backingInt(Part.hostile_reason)], .{}),
                try textHash(a, trusted),
                try textHash(a, reflow),
            }),
        }
    }
    var dropped: usize = 0;
    if (old) |b| {
        var it = b.keyIterator();
        while (it.next()) |id| {
            if (seen.contains(id.*)) continue;
            dropped += 1;
            std.debug.print("REFROZE\t{s}\t{s}\tdropped\n", .{ label, id.* });
        }
    }
    try dir.writeFile(io, .{ .sub_path = path, .data = out.items });
    if (old == null) {
        std.debug.print("== {s}: frozen, {d} cases, the first answers ({s})\n", .{ label, cases.len, path });
    } else {
        std.debug.print("== {s}: refrozen, {d} cases: {d} changed, {d} added, {d} dropped ({s})\n", .{ label, cases.len, changed, added, dropped, path });
    }
    return t;
}

// ── the hostile shapes ──────────────────────────────────────────────────────

/// A shape a unit repeated, on one side or two: `head`, `unit` n times,
/// `middle`, `after` n times, `tail`. `sizes`, when set, replaces its
/// list's sizes for that shape. The documented adversarial shapes
/// (chat-markdown's markdown_hostile_probe.zig's), cmark's pathological
/// tests (test/pathological_tests.py), and the dialect's own corners: the
/// fence cap, the nesting cap, the email floor.
const Shape = struct {
    name: []const u8,
    head: []const u8 = "",
    unit: []const u8,
    middle: []const u8 = "",
    after: []const u8 = "",
    tail: []const u8 = "",
    sizes: ?[]const usize = null,
};

fn build(a: std.mem.Allocator, s: Shape, n: usize) ![]const u8 {
    var md: std.ArrayList(u8) = .empty;
    try md.appendSlice(a, s.head);
    for (0..n) |_| try md.appendSlice(a, s.unit);
    try md.appendSlice(a, s.middle);
    for (0..n) |_| try md.appendSlice(a, s.after);
    try md.appendSlice(a, s.tail);
    return md.items;
}

const shapes = [_]Shape{
    // markdown_hostile_probe.zig's.
    .{ .name = "open-brackets", .unit = "[" },
    .{ .name = "link-bait", .unit = "[](" },
    .{ .name = "emph-underscore", .unit = "a_b_" },
    .{ .name = "emph-star", .unit = "*" },
    .{ .name = "backticks", .unit = "`" },
    .{ .name = "angle-brackets", .unit = "<" },
    .{ .name = "nested-quote", .unit = "> " },
    .{ .name = "msg-ref-bait", .unit = "MSG_a_1 " },
    .{ .name = "dense-legit", .unit = "**x** " },
    // cmark's pathological tests.
    .{ .name = "nested-strong-emph", .unit = "*a **a ", .tail = "b" },
    .{ .name = "nested-strong-emph-close", .head = "b", .unit = " a** a*" },
    .{ .name = "emph-closers-no-openers", .unit = "a_ " },
    .{ .name = "emph-openers-no-closers", .unit = "_a " },
    .{ .name = "link-closers-no-openers", .unit = "a]" },
    .{ .name = "link-openers-no-closers", .unit = "[a" },
    .{ .name = "mismatched-openers-closers", .unit = "*a_ " },
    .{ .name = "openers-closers-mod-3", .head = "a**b", .unit = "c* " },
    .{ .name = "link-openers-emph-closers", .unit = "[ a_" },
    .{ .name = "paren-bracket", .unit = "[ (](" },
    .{ .name = "nested-brackets", .unit = "[", .tail = "a" },
    .{ .name = "nested-brackets-close", .head = "a", .unit = "]" },
    .{ .name = "nested-quotes-a", .unit = "> ", .tail = "a" },
    .{ .name = "nul-bytes", .unit = "abc\x00de\x00" },
    .{ .name = "unclosed-links-a", .unit = "[a](<b" },
    .{ .name = "unclosed-links-b", .unit = "[a](b" },
    .{ .name = "unclosed-comments", .head = "</", .unit = "<!--" },
    .{ .name = "tabs", .head = "- ", .unit = "\t", .tail = "a" },
    .{ .name = "backslashes", .unit = "\\" },
    .{ .name = "entities", .unit = "&#x" },
    // The dialect's corners.
    .{ .name = "emails-dead", .unit = "a_b." },
    .{ .name = "email-ats", .unit = "a@" },
    .{ .name = "emails", .unit = "a.b@c.d " },
    .{ .name = "www", .unit = "www." },
    .{ .name = "urls", .unit = "http://a.b/(c) " },
    .{ .name = "url-parens", .head = "http://a.b/", .unit = ")" },
    .{ .name = "code-spans", .unit = "`a` " },
    .{ .name = "code-runs", .unit = "``` " },
    .{ .name = "img-bait", .unit = "<img src=\"/a.png\"" },
    .{ .name = "imgs", .unit = "<img src=\"/a.png\" alt=x>" },
    .{ .name = "videos", .unit = "<video src=\"/v.mp4\"></video>" },
    .{ .name = "links", .unit = "[t](http://x.com) " },
    .{ .name = "msg-bait", .unit = "MSG_" },
    .{ .name = "fences", .unit = "~~~\n" },
    .{ .name = "fences-backtick", .unit = "```\n" },
    .{ .name = "headings", .unit = "# a\n" },
    .{ .name = "bullets", .unit = "- " },
    .{ .name = "bullet-lines", .unit = "- a\n" },
    .{ .name = "ordered-lines", .unit = "1. a\n" },
    .{ .name = "loose-lines", .unit = "- a\n\n" },
    .{ .name = "html-block-lines", .unit = "<div>\n" },
    .{ .name = "quote-lines", .unit = ">a\n" },
    .{ .name = "hard-wraps", .unit = "a\n" },
    .{ .name = "blank-lines", .unit = "\n" },
    .{ .name = "words", .unit = "word " },
    .{ .name = "mixed", .unit = "*a* _b_ `c` [d](e) MSG_f_1 g@h.i www.j.k\n" },
};

const sizes = [_]usize{ 1, 2, 3, 4, 10, 100, 1000 };

/// Other renderers' pathological shapes, at `deep_sizes`, whose 8191 is the
/// largest count roc-parser's fuzzer draws.
const deep_shapes = [_]Shape{
    // grayrest/roc-markdown's pathological expects (package/Test.roc 402-651).
    .{ .name = "gr-tag-openers-one-closer", .unit = "<a", .tail = ">" },
    .{ .name = "gr-bracket-openers-one-closer", .unit = "[", .tail = "]" },
    .{ .name = "gr-cdata-openers-one-closer", .head = "a ", .unit = "<![CDATA[", .tail = ">" },
    .{ .name = "gr-full-references", .unit = "[a][b] ", .tail = "\n\n[b]: /u" },
    .{ .name = "gr-unclosed-angle-dests", .unit = "[a](<" },
    .{ .name = "gr-unclosed-angle-dests-one-closer", .unit = "[a](<", .tail = ">" },
    .{ .name = "gr-angle-openers-in-a-dest", .head = "[a](", .unit = "<" },
    .{ .name = "gr-unclosed-inline-links", .unit = "[a](" },
    .{ .name = "gr-many-attributes", .head = "a <a", .unit = " b=\"c\"", .tail = ">" },
    .{ .name = "gr-escaped-stars", .unit = "\\*" },
    .{ .name = "gr-label-length", .head = "[", .unit = "a", .middle = "]\n\n[", .after = "a", .tail = "]: /u", .sizes = &.{ 999, 1000 } },
    .{ .name = "gr-emph-run-nest", .unit = "*", .middle = "a", .after = "*" },
    .{ .name = "gr-emph-separate-nest", .unit = "*a ", .after = " a*" },
    .{ .name = "gr-url-close-parens", .head = "https://a", .unit = ")" },
    // grayrest's with a dotted host, which the autolink needs before it
    // trims: quadratic in a urlEnd that recounts the parens for each `)`
    // it trims.
    .{ .name = "url-close-parens-dotted", .head = "https://a.b", .unit = ")" },
    .{ .name = "www-close-parens", .head = "www.a.b", .unit = ")" },
    .{ .name = "gr-nested-full-references", .unit = "[", .middle = "a", .after = "][x]" },
    .{ .name = "gr-label-of-tag-openers", .head = "[", .unit = "<a", .tail = ">]" },
    .{ .name = "gr-bang-quote-openers", .head = "a ", .unit = "<!\"", .tail = "'>" },
    .{ .name = "gr-label-of-quote-pairs", .head = "[<a ", .unit = "\"x\"", .tail = ">]" },
    .{ .name = "gr-emphases", .unit = "*a* " },
    // lukewilliamboswell/roc-parser fuzz/markdown-inline-pathological.roc:
    // the two-sided ones, and the one-sided ones the shapes above lack.
    .{ .name = "lb-nested-strong-emph", .unit = "*a **a ", .middle = "b", .after = " a** a*" },
    .{ .name = "lb-nested-brackets", .unit = "[", .middle = "a", .after = "]" },
    .{ .name = "lb-nested-links", .unit = "[", .middle = "a", .after = "](u)" },
    .{ .name = "lb-nested-images", .unit = "![", .middle = "a", .after = "](u)" },
    .{ .name = "lb-emph-in-links", .unit = "[*a", .after = "*](u)" },
    .{ .name = "lb-mixed-delimiters", .unit = "*_", .middle = "x", .after = "_*" },
    .{ .name = "lb-mixed-delimiters-tilde", .unit = "*_~", .middle = "x", .after = "~_*" },
    .{ .name = "lb-nested-parens-in-dest", .head = "[a](", .unit = "(", .middle = "b", .after = ")", .tail = ")" },
    .{ .name = "lb-www-autolinks", .unit = " www.a.b(", .after = ")" },
    .{ .name = "lb-scheme-autolinks", .unit = "http://a.b/x?" },
    .{ .name = "lb-email-autolinks", .unit = "a.b@c", .after = "@d.e " },
    .{ .name = "lb-many-at-signs", .unit = "@", .middle = "a", .after = ".b@" },
    .{ .name = "lb-long-words-before-colon", .unit = "abc", .middle = "://", .after = ":" },
    .{ .name = "lb-backtick-runs", .unit = "e`", .after = "e``" },
    .{ .name = "lb-tilde-runs", .unit = "~a ", .after = " a~" },
    .{ .name = "lb-reference-like-brackets", .unit = "[a][", .after = "]" },
    .{ .name = "lb-unclosed-links-c", .unit = "[a](b \"" },
    // A destination's parens balance (QUEUE 311): opens never closed, closes
    // past the balance, a `](` each with an open paren, and links that each
    // nest a pair, all linear by the one paren pass a line.
    .{ .name = "rm-unbalanced-open-parens", .head = "[a](", .unit = "(", .tail = "b" },
    .{ .name = "rm-unbalanced-close-parens", .head = "[a](b", .unit = ")" },
    .{ .name = "rm-paren-bait", .unit = "[a]((" },
    .{ .name = "rm-paren-links", .unit = "[a](b(c)) " },
    // GFM's tables (QUEUE 311): a header row n cells wide, its delimiter as
    // wide, and a one-cell row padded to n; n body rows; a delimiter row
    // alone, again and again (the first two lines are a table, the rest its
    // rows); pipes in code spans, which split a cell all the same, a row's
    // worth and a header's width.
    .{ .name = "tbl-wide", .unit = "| a ", .middle = "|\n", .after = "| - ", .tail = "|\n| x |\n" },
    .{ .name = "tbl-many-rows", .head = "| a | b |\n| - | - |\n", .unit = "| x | *y* |\n" },
    .{ .name = "tbl-delimiter-alone", .unit = "|---|\n" },
    .{ .name = "tbl-code-pipes", .head = "| a | b |\n| - | - |\n", .unit = "| `|` | `\\|` |\n" },
    .{ .name = "tbl-code-pipes-wide", .unit = "`a|b` ", .middle = "\n", .after = "-|", .tail = "-\n`a|b`\n" },
    .{ .name = "lb-unclosed-processing-instructions", .unit = "<?" },
    .{ .name = "lb-unclosed-declarations", .unit = "<!A" },
    .{ .name = "lb-unclosed-open-tags", .unit = "<a b='" },
    .{ .name = "lb-unclosed-autolinks", .unit = "<http:a" },
    .{ .name = "lb-entity-prefixes", .unit = "&#", .after = "&a" },
    .{ .name = "lb-hard-breaks", .unit = "a  \n", .after = "b\\\n" },
};

const deep_sizes = [_]usize{ 1, 10, 100, 1000, 8191 };

/// Every shape at every size, and the two shapes that are no repeat: a list
/// whose every line indents one level more (the nesting cap), and a run of
/// backtick runs each one longer (cmark's "backticks").
pub fn hostileCases(a: std.mem.Allocator) ![]Case {
    var cases: std.ArrayList(Case) = .empty;
    const lists = [_]struct { shapes: []const Shape, sizes: []const usize }{
        .{ .shapes = &shapes, .sizes = &sizes },
        .{ .shapes = &deep_shapes, .sizes = &deep_sizes },
    };
    for (lists) |list| for (list.shapes) |s| {
        for (s.sizes orelse list.sizes) |n| {
            try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/{s}/{d}", .{ s.name, n }), .md = try build(a, s, n) });
        }
    };
    for ([_]usize{ 2, 17, 40, 200 }) |n| {
        var stair: std.ArrayList(u8) = .empty;
        var ticks: std.ArrayList(u8) = .empty;
        var quotes: std.ArrayList(u8) = .empty;
        try ticks.append(a, 'e');
        for (0..n) |i| {
            for (0..i * 2) |_| try stair.append(a, ' ');
            try stair.appendSlice(a, "- a\n");
            for (0..i + 1) |_| try ticks.append(a, '`');
            try ticks.append(a, ' ');
            for (0..i + 1) |_| try quotes.append(a, '>');
            try quotes.appendSlice(a, " a\n");
        }
        try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/list-stair/{d}", .{n}), .md = stair.items });
        try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/backtick-stair/{d}", .{n}), .md = ticks.items });
        try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/quote-stair/{d}", .{n}), .md = quotes.items });
        // A table n wide and n rows of one cell: n² cells out of 4n bytes,
        // the padding its source never paid for, so the budget's to stop.
        var ragged: std.ArrayList(u8) = .empty;
        for (0..n) |_| try ragged.appendSlice(a, "|a");
        try ragged.appendSlice(a, "|\n");
        for (0..n) |_| try ragged.appendSlice(a, "|-");
        try ragged.appendSlice(a, "|\n");
        for (0..n) |_| try ragged.appendSlice(a, "x\n");
        try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/tbl-ragged/{d}", .{n}), .md = ragged.items });
    }
    // **ACROSS THE BUDGET'S EDGE**: a run of backtick runs each one longer
    // is quadratic (each unmatched run scans to the line's end), so as n
    // grows it crosses the ceiling, at a different charge each n. Swept in
    // every context a line renders in, so each check point (a block line,
    // an inline step, a label's, emphasis's) is the one that trips.
    const contexts = [_][2][]const u8{
        .{ "", "" },                     .{ "# ", "" },                .{ "- ", "" },
        .{ "> ", "" },                   .{ "[", "](u)" },             .{ "*a* _b_ ", " **c** *d* _e_" },
        .{ "text\n", "\nmore\n\nnext" }, .{ "```\n", "\n```\nafter" }, .{ "- a\n  - ", "\n- b" },
    };
    for (contexts, 0..) |ctx, ci| {
        var n: usize = 20;
        while (n <= 140) : (n += 3) {
            var md: std.ArrayList(u8) = .empty;
            try md.appendSlice(a, ctx[0]);
            for (0..n) |i| {
                for (0..i + 1) |_| try md.append(a, '`');
                try md.append(a, 'x');
            }
            try md.appendSlice(a, ctx[1]);
            try cases.append(a, .{ .id = try std.fmt.allocPrint(a, "hostile/edge/{d}/{d}", .{ ci, n }), .md = md.items });
        }
    }
    return cases.items;
}

// ── the spec check ──────────────────────────────────────────────────────────

/// `render`'s html as the spec writes it: our hard break (`<br>\n`) as its
/// soft one (`\n`), and an external link's new-tab attributes gone.
fn specNormal(a: std.mem.Allocator, html: []const u8) ![]const u8 {
    const soft = try std.mem.replaceOwned(u8, a, html, "<br>\n", "\n");
    return std.mem.replaceOwned(u8, a, soft, " target=\"_blank\" rel=\"noopener\"", "");
}

/// spec_diverge.txt's ids: a line a case, its id before the first tab;
/// `#` lines and blank ones are its commentary.
fn readDiverge(io: Io, dir: Io.Dir, a: std.mem.Allocator) !std.StringHashMapUnmanaged(void) {
    const data = dir.readFileAlloc(io, spec_diverge_path, a, .unlimited) catch |e| {
        std.debug.print("cannot read {s}: {s}\n", .{ spec_diverge_path, @errorName(e) });
        return e;
    };
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse line.len;
        try ids.put(a, line[0..tab], {});
    }
    return ids;
}

/// **THE PACKAGE AGAINST COMMONMARK, WITH ITS DIVERGENCES LISTED**: each
/// spec case's `render`, normalised (specNormal), against the spec's html.
/// A case that differs must be in spec_diverge.txt, with its reason, and a
/// listed one that matches fails too (`SPECSTALE`), so the list says what
/// is true today. The frozen answers hold the package still; this says
/// where still is, against the spec. Gives the failures.
fn specCheck(io: Io, dir: Io.Dir, arena: *std.heap.ArenaAllocator, sa: std.mem.Allocator, cases: []const Case) !usize {
    var listed = try readDiverge(io, dir, sa);
    var fails: usize = 0;
    var agree: usize = 0;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (cases) |c| {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();
        try seen.put(sa, c.id, {});
        const spec = c.html orelse {
            fails += 1;
            std.debug.print("SPECFAIL\t{s}\tthe case has no html, the spec's\n", .{c.id});
            continue;
        };
        const ours = switch (try rocAnswers(a, c.md)) {
            .answers => |g| g[@backingInt(Part.render)],
            .answered => {
                fails += 1;
                std.debug.print("SPECFAIL\t{s}\tthe package gave no answers\n", .{c.id});
                continue;
            },
        };
        const same = std.mem.eql(u8, try specNormal(a, ours), spec);
        if (same) agree += 1;
        if (same and listed.contains(c.id)) {
            fails += 1;
            std.debug.print("SPECSTALE\t{s}\tmatches CommonMark now: take it out of {s}\n", .{ c.id, spec_diverge_path });
        } else if (!same and !listed.contains(c.id)) {
            fails += 1;
            std.debug.print("SPECFAIL\t{s}\tdiffers from CommonMark, and {s} does not list it\n", .{ c.id, spec_diverge_path });
        }
    }
    var it = listed.keyIterator();
    while (it.next()) |id| {
        if (seen.contains(id.*)) continue;
        fails += 1;
        std.debug.print("SPECSTALE\t{s}\tlisted in {s}, and no spec corpus's case\n", .{ id.*, spec_diverge_path });
    }
    std.debug.print("== spec: {d}/{d} match CommonMark, {d} listed as diverging ({d} fail)\n", .{ agree, cases.len, listed.count(), fails });
    return fails;
}

// ── the ratchet ─────────────────────────────────────────────────────────────

const Rung = struct { label: []const u8, pass: usize };

/// ratchet.txt's lines, `<label> <pass count>`.
fn readRatchet(io: Io, dir: Io.Dir, a: std.mem.Allocator) ![]Rung {
    const data = dir.readFileAlloc(io, ratchet_path, a, .unlimited) catch |e| switch (e) {
        error.FileNotFound => return &.{},
        else => return e,
    };
    var rungs: std.ArrayList(Rung) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return error.RatchetLineHasNoCount;
        try rungs.append(a, .{ .label = line[0..sp], .pass = try std.fmt.parseInt(usize, line[sp + 1 ..], 10) });
    }
    return rungs.items;
}

fn rungFor(rungs: []const Rung, label: []const u8) ?usize {
    for (rungs) |r| if (std.mem.eql(u8, r.label, label)) return r.pass;
    return null;
}

const Result = struct { label: []const u8, t: Tally, ratcheted: bool };

fn writeRatchet(io: Io, dir: Io.Dir, a: std.mem.Allocator, results: []const Result) !void {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, "# The judge's pass counts (judge/judge.zig): each may only rise.\n");
    for (results) |r| if (r.ratcheted) try out.print(a, "{s} {d}\n", .{ r.label, r.t.pass });
    try dir.writeFile(io, .{ .sub_path = ratchet_path, .data = out.items });
}

fn usage() noreturn {
    std.debug.print("arguments: --also PATH, --refreeze LABEL, --raise, --time, --data DIR\n", .{});
    std.process.exit(2);
}

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = std.heap.page_allocator;
    var setup = std.heap.ArenaAllocator.init(alloc);
    defer setup.deinit();
    const sa = setup.allocator();

    var also: std.ArrayList([]const u8) = .empty;
    var refreezing: std.ArrayList([]const u8) = .empty;
    var raise = false;
    var timed = false;
    // The data folder: the build's judge/data, or `--data DIR`, a copy of it
    // (tools/verify.shale plants its faults in one, never in the tree).
    var data_folder: []const u8 = data_path;
    const args = try init.minimal.args.toSlice(sa);
    var k: usize = 1;
    while (k < args.len) : (k += 1) {
        const arg = args[k];
        if (std.mem.eql(u8, arg, "--raise")) {
            raise = true;
        } else if (std.mem.eql(u8, arg, "--time")) {
            timed = true;
        } else if (std.mem.eql(u8, arg, "--also") and k + 1 < args.len) {
            k += 1;
            try also.append(sa, args[k]);
        } else if (std.mem.eql(u8, arg, "--data") and k + 1 < args.len) {
            k += 1;
            data_folder = args[k];
        } else if (std.mem.eql(u8, arg, "--refreeze") and k + 1 < args.len) {
            k += 1;
            try refreezing.append(sa, args[k]);
        } else usage();
    }

    roc.use(alloc);
    defer roc.deinit();

    const data = Io.Dir.cwd().openDir(io, data_folder, .{}) catch |e| {
        std.debug.print("cannot open the judge's data {s}: {s}\n", .{ data_folder, @errorName(e) });
        return e;
    };
    defer data.close(io);
    const cwd = Io.Dir.cwd();

    // The corpora: the list's (ratcheted), the hostile shapes (ratcheted),
    // then each --also (counted, never ratcheted); each with its answers'
    // path, beside it, in its folder.
    const Corpus = struct { label: []const u8, cases: []const Case, ratcheted: bool, dir: Io.Dir, answers: []const u8, keep: Keep };
    var corpora: std.ArrayList(Corpus) = .empty;
    const list = try data.readFileAlloc(io, corpora_list, sa, .unlimited);
    var lines = std.mem.splitScalar(u8, list, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        try corpora.append(sa, .{ .label = labelOf(line), .cases = try readCorpus(io, data, sa, line), .ratcheted = true, .dir = data, .answers = try answersPathOf(sa, line), .keep = .whole });
    }
    try corpora.append(sa, .{ .label = "hostile", .cases = try hostileCases(sa), .ratcheted = true, .dir = data, .answers = hostile_answers_path, .keep = .hashed });
    for (also.items) |path| try corpora.append(sa, .{ .label = labelOf(path), .cases = try readCorpus(io, cwd, sa, path), .ratcheted = false, .dir = cwd, .answers = try answersPathOf(sa, path), .keep = .whole });
    for (corpora.items, 0..) |c, i| {
        for (corpora.items[0..i]) |d| if (std.mem.eql(u8, c.label, d.label)) {
            std.debug.print("two corpora are labelled {s}: a re-freeze would not know which\n", .{c.label});
            std.process.exit(2);
        };
    }
    for (refreezing.items) |label| {
        for (corpora.items) |c| {
            if (std.mem.eql(u8, c.label, label)) break;
        } else {
            std.debug.print("--refreeze {s}: no corpus of this run is labelled so (a private corpus needs its --also)\n", .{label});
            std.process.exit(2);
        }
    }

    const rungs = try readRatchet(io, data, sa);
    var results: std.ArrayList(Result) = .empty;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    var fell = false;
    var unrecorded = false;
    var total: Tally = .{};
    for (corpora.items) |c| {
        const t = if (contains(refreezing.items, c.label))
            try refreeze(io, &arena, c.label, c.cases, c.keep, try readAnswers(io, c.dir, sa, c.answers), c.dir, c.answers)
        else if (try readAnswers(io, c.dir, sa, c.answers)) |book|
            try judgeFrozenCases(&arena, c.label, c.cases, &book)
        else {
            std.debug.print("== {s}: NO ANSWERS at {s}: --refreeze {s} records them\n", .{ c.label, c.answers, c.label });
            unrecorded = true;
            continue;
        };
        total.pass += t.pass;
        total.fail += t.fail;
        total.hostile += t.hostile;
        try results.append(sa, .{ .label = c.label, .t = t, .ratcheted = c.ratcheted });
        std.debug.print("== {s}: {d}/{d} hold to their answers ({d} fail; {d} hostile)", .{ c.label, t.pass, t.pass + t.fail, t.fail, t.hostile });
        if (c.ratcheted) {
            const floor = rungFor(rungs, c.label) orelse 0;
            if (t.pass < floor) {
                fell = true;
                std.debug.print("  BELOW THE RATCHET ({d})", .{floor});
            } else if (t.pass > floor) {
                std.debug.print("  the ratchet ({d}) can rise: --raise", .{floor});
            }
        }
        std.debug.print("\n", .{});
        if (timed) try timeCorpus(&arena, c.cases);
    }
    var spec_cases: std.ArrayList(Case) = .empty;
    var spec_found: usize = 0;
    for (corpora.items) |c| {
        if (!contains(&spec_labels, c.label)) continue;
        try spec_cases.appendSlice(sa, c.cases);
        spec_found += 1;
    }
    const spec_checked = spec_found == spec_labels.len;
    const spec_fails = try specCheck(io, data, &arena, sa, spec_cases.items);
    std.debug.print("==> {d}/{d} hold to their answers ({d} fail; {d} hostile)\n", .{ total.pass, total.pass + total.fail, total.fail, total.hostile });
    if (fell) std.debug.print("a corpus fell below its ratchet ({s})\n", .{ratchet_path});
    if (unrecorded) std.debug.print("a corpus has no answers\n", .{});
    if (!spec_checked) std.debug.print("the spec check wants corpora labelled {s} and {s}: {d} of them are here\n", .{ spec_labels[0], spec_labels[1], spec_found });
    if (spec_fails > 0) std.debug.print("the spec check failed: {s} is not what the package does today\n", .{spec_diverge_path});
    if (fell or unrecorded or total.fail > 0 or !spec_checked or spec_fails > 0) std.process.exit(1);
    if (raise) {
        try writeRatchet(io, data, sa, results.items);
        std.debug.print("ratchet rewritten: {s}\n", .{ratchet_path});
    }
}

/// A corpus's render time: the whole call, which answers all five.
fn timeCorpus(arena: *std.heap.ArenaAllocator, cases: []const Case) !void {
    var ms: f64 = 0;
    for (cases) |c| {
        _ = arena.reset(.retain_capacity);
        const t0 = cpuMs();
        _ = try roc.answers(arena.allocator(), c.md);
        ms += cpuMs() - t0;
    }
    std.debug.print("   time: {d:.1} ms (all five answers each)\n", .{ms});
}

/// The process's CPU time so far, in milliseconds.
fn cpuMs() f64 {
    const r = std.posix.getrusage(std.posix.rusage.SELF);
    const us = (r.utime.sec + r.stime.sec) * std.time.us_per_s + r.utime.usec + r.stime.usec;
    return @as(f64, @floatFromInt(us)) / 1000;
}
