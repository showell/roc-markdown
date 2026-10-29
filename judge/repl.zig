//! **THE PACKAGE AT A PROMPT** (`zig build repl`): type markdown, see what
//! the package makes of it. Each block's five answers come from the judge's
//! seam (judge/answers.roc through roc_host.zig), so the REPL shows what
//! the judge holds: the mode's html, the work units and the hostility
//! verdict, and for a hostile message what the chat answers instead.
//!
//! **A BLOCK** is the lines typed, each with its newline, up to an empty
//! line, which ends it and is not part of it. A block that has empty lines
//! inside (a loose list, a fence) begins with an empty line, and two empty
//! lines in a row end it. `:load PATH` renders a file's bytes exactly, for
//! any text these rules cannot type. End of input ends the last block and
//! quits.
//!
//! **A COMMAND** is a line starting with `:` where a block would begin;
//! inside a block such a line is markdown. `help` below lists them.
//!
//! **PIPED, IT IS PLAIN**: when stdin is not a terminal there is no banner
//! and no prompt, a mode switch says nothing, and a command that fails
//! stops the run (exit 1), so a script never carries on past a mistake.
//!
//! **THE CANNED EXAMPLES** are judge/data/examples.jsonl, a corpus of the
//! judge too, so their answers are frozen there.

const std = @import("std");
const Io = std.Io;
const roc = @import("roc_host.zig");

/// The renders the REPL can show, each one of the five answers.
pub const Mode = enum {
    chat,
    trusted,
    reflow,

    pub fn part(m: Mode) roc.Part {
        return switch (m) {
            .chat => .render,
            .trusted => .trusted,
            .reflow => .trusted_reflow,
        };
    }

    fn what(m: Mode) []const u8 {
        return switch (m) {
            .chat => "Md.render: a member's message, with its budget; a newline is a <br>",
            .trusted => "Md.render_trusted: server-owned text, no budget; a newline is a <br>",
            .reflow => "Md.render_trusted_reflow: server-owned prose, no budget; a newline is a space",
        };
    }
};

/// One block's answer, as the REPL prints it: the html (a newline added
/// where it lacks one), the work units, the verdict, and for a hostile
/// message the words the chat refuses it with.
pub fn writeBlock(w: *Io.Writer, html: []const u8, units: []const u8, hostile: []const u8) Io.Writer.Error!void {
    try w.writeAll(html);
    if (html.len > 0 and html[html.len - 1] != '\n') try w.writeByte('\n');
    try w.print("work units: {s}\n", .{units});
    if (hostile.len == 0)
        try w.writeAll("hostility: Renderable\n")
    else
        try w.print("hostility: TooMuchFormatting (the chat refuses the message: \"{s}\")\n", .{hostile});
}

/// A canned example: judge/data/examples.jsonl's line.
pub const Example = struct { id: []const u8, caption: []const u8, md: []const u8 };

pub const examples_jsonl = @embedFile("data/examples.jsonl");

pub fn examples(a: std.mem.Allocator) ![]Example {
    var out: std.ArrayList(Example) = .empty;
    var lines = std.mem.splitScalar(u8, examples_jsonl, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try out.append(a, try std.json.parseFromSliceLeaky(Example, a, line, .{}));
    }
    return out.items;
}

const help =
    \\A block: the lines you type, up to an empty line. Begin with an empty
    \\line for a block with empty lines inside (a loose list, a fence); two
    \\empty lines in a row end it. End of input quits.
    \\
    \\  :mode             the mode now
    \\  :mode chat        Md.render: the chat's, with its budget (the start)
    \\  :mode trusted     Md.render_trusted: docs, no budget
    \\  :mode reflow      Md.render_trusted_reflow: docs, newlines as spaces
    \\  :examples         the canned examples, each named with its caption
    \\  :ex NAME          one example: its source, then its answer
    \\  :load PATH        a file's bytes, exactly (PATH from the repo's root)
    \\  :help             this
    \\  :quit             quit (so does end of input)
    \\
;

const State = enum { idle, short, long };

const Repl = struct {
    io: Io,
    a: std.mem.Allocator,
    out: *Io.Writer,
    tty: bool,
    mode: Mode = .chat,
    examples: []Example,

    /// The package's answers for `md`, printed for the mode.
    fn render(r: *Repl, md: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(r.a);
        defer arena.deinit();
        const got = try roc.answers(arena.allocator(), md);
        if (got.len != std.enums.values(roc.Part).len) std.debug.panic("the package gave {d} answers", .{got.len});
        try writeBlock(r.out, got[@backingInt(r.mode.part())], got[@backingInt(roc.Part.work_units)], got[@backingInt(roc.Part.hostile_reason)]);
    }

    /// A command's failure: said, and in plain mode the end of the run.
    fn fail(r: *Repl, comptime fmt: []const u8, args: anytype) !void {
        if (r.tty) {
            try r.out.print(fmt ++ "\n", args);
            return;
        }
        try r.out.flush();
        std.debug.print("repl: " ++ fmt ++ "\n", args);
        std.process.exit(1);
    }

    /// A command line; false to quit.
    fn command(r: *Repl, line: []const u8) !bool {
        const text = std.mem.trim(u8, line[1..], " \t\r");
        const sp = std.mem.indexOfAny(u8, text, " \t") orelse text.len;
        const name = text[0..sp];
        const rest = std.mem.trim(u8, text[sp..], " \t");
        if (eql(name, "quit") or eql(name, "q")) return false;
        if (eql(name, "help")) {
            try r.out.writeAll(help);
        } else if (eql(name, "mode")) {
            if (rest.len == 0) {
                try r.out.print("mode: {t} ({s})\n", .{ r.mode, r.mode.what() });
            } else if (std.meta.stringToEnum(Mode, rest)) |m| {
                r.mode = m;
                if (r.tty) try r.out.print("mode: {t} ({s})\n", .{ m, m.what() });
            } else try r.fail("no mode `{s}`: chat, trusted or reflow", .{rest});
        } else if (eql(name, "examples")) {
            for (r.examples) |e| try r.out.print("  {s: <10} {s}\n", .{ e.id, e.caption });
        } else if (eql(name, "ex")) {
            for (r.examples) |e| {
                if (!eql(e.id, rest)) continue;
                try r.out.print("── {s}: {s}\n", .{ e.id, e.caption });
                try r.out.writeAll(e.md);
                if (e.md.len > 0 and e.md[e.md.len - 1] != '\n') try r.out.writeByte('\n');
                try r.out.print("── {t}:\n", .{r.mode});
                try r.render(e.md);
                break;
            } else try r.fail("no example `{s}` (:examples lists them)", .{rest});
        } else if (eql(name, "load")) {
            if (rest.len == 0) {
                try r.fail(":load needs a path", .{});
                return true;
            }
            const bytes = Io.Dir.cwd().readFileAlloc(r.io, rest, r.a, .unlimited) catch |e| {
                try r.fail("cannot read {s}: {t}", .{ rest, e });
                return true;
            };
            defer r.a.free(bytes);
            try r.render(bytes);
        } else try r.fail("no command `:{s}` (:help lists them)", .{name});
        return true;
    }
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const a = std.heap.page_allocator;
    roc.use(a);
    defer roc.deinit();

    var out_buf: [64 * 1024]u8 = undefined;
    var fw = Io.File.stdout().writer(io, &out_buf);
    const in_buf = try a.alloc(u8, 1 << 20);
    defer a.free(in_buf);
    var fr = Io.File.stdin().readerStreaming(io, in_buf);
    const in = &fr.interface;

    var ex_arena = std.heap.ArenaAllocator.init(a);
    defer ex_arena.deinit();
    var r: Repl = .{
        .io = io,
        .a = a,
        .out = &fw.interface,
        .tty = try Io.File.stdin().isTty(io),
        .examples = try examples(ex_arena.allocator()),
    };
    if (r.tty) {
        try r.out.writeAll("roc-markdown: type markdown, then an empty line. :help for the commands, :examples for a tour.\n");
        try r.out.writeAll("A block with empty lines inside: begin it with an empty line, end it with two.\n");
    }

    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(a);
    var state: State = .idle;
    var blanks: usize = 0;
    while (true) {
        if (r.tty) {
            try r.out.writeAll(switch (state) {
                .idle => "md> ",
                .short => "..> ",
                .long => "::> ",
            });
        }
        try r.out.flush();
        const got = in.takeDelimiter('\n') catch |e| switch (e) {
            error.StreamTooLong => {
                try r.fail("a line longer than 1 MiB: :load it from a file", .{});
                _ = try in.discardDelimiterInclusive('\n');
                continue;
            },
            else => return e,
        };
        const line = got orelse {
            if (state != .idle) try r.render(block.items);
            break;
        };
        switch (state) {
            .idle => if (line.len > 0 and line[0] == ':') {
                if (!try r.command(line)) break;
            } else if (line.len == 0) {
                state = .long;
                blanks = 0;
            } else {
                try block.appendSlice(a, line);
                try block.append(a, '\n');
                state = .short;
            },
            .short => if (line.len == 0) {
                try r.render(block.items);
                block.clearRetainingCapacity();
                state = .idle;
            } else {
                try block.appendSlice(a, line);
                try block.append(a, '\n');
            },
            .long => if (line.len == 0) {
                blanks += 1;
                if (blanks == 2) {
                    try r.render(block.items);
                    block.clearRetainingCapacity();
                    state = .idle;
                }
            } else {
                if (blanks == 1) try block.append(a, '\n');
                blanks = 0;
                try block.appendSlice(a, line);
                try block.append(a, '\n');
            },
        }
    }
    try r.out.flush();
}
