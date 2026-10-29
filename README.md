# roc-markdown

The markdown dialect of Gopher Chat (lynrummy.com/chat), rendered to HTML, in
Roc, as a Roc package with no dependencies and no platform: pure functions
from bytes to bytes.

**The renderer is the definition of the dialect.** It began as a byte-for-byte
port of chat-markdown's Zig, and **diverges from it from 2026-10-29 on**: the
Zig is no longer its judge. Its judge is a set of frozen answers (below).

## The dialect

- Paragraphs, ATX headings, lists, blockquotes and fenced code; a list or a
  quote nested past 16 levels renders as one flat paragraph.
- **GFM's pipe tables**, as the GFM spec writes them: a header row, a
  delimiter row (`:` for `align`), body rows cut or padded to the header's
  width, `\|` for a pipe in a cell (in a code span too). A table may
  follow a paragraph's line directly. Its HTML is the spec's own: `table`,
  `thead`, `tbody`, `tr`, `th`, `td` and `align="left|center|right"`, no
  class.
- **Inline markup is per line**: `**`, `*`, `_`, backticks and `[...](...)`
  never pair across a line break.
- **A newline is a `<br>`** (`render`, `render_trusted`), or a space for
  server-owned prose (`render_trusted_reflow`).
- **Raw HTML is escaped**, except a same-origin `<img>` or `<video>`, which
  is rebuilt from its safe attributes alone.
- A ```` ```quote ```` fence is a reply's quote, not code.
- `MSG_<slug>` is a link to that message (`#msg-<slug>`).
- A link to another site, written or bare (`http://`, `www.`), opens in a new
  tab; an email address is a `mailto:` link.
- **A work budget refuses hostile input.** A render charges its work to a
  budget sized by the input; a message that blows it renders as
  `Md.malformed_html`, and `Md.hostility` says so first, so a host can refuse
  it. `Md.work_units` is the work a render costs. The trusted renders have no
  budget.

## Use

In an app's header, by path (the Roc this is built with, nightly-2026-10-09,
takes a local package so):

```roc
app [main!] {
	pf: platform "...",
	md: "../../roc-markdown/package/main.roc",
}

import md.Md
```

The package exposes `Md` (the renders and the budget's verdict), `MdFence`
(a fence's open and close) and `MdMedia` (a stored image tag rebuilt), which
a host's code and image feeds read.

```
roc check package/main.roc
roc test package/main.roc
roc fmt --check package
```

## Its judge

The judge (`judge/judge.zig`, a Zig program calling the package through
`judge/answers.roc` on `judge/platform/`) holds every case of its corpora
(`judge/data/`) to the answers frozen for it: each render's html, the work
units, the hostility verdict, and both trusted renders. A case's answers
change only by an explicit re-freeze (`--refreeze LABEL`), which names the
cases that moved. Each corpus's pass count is held to
`judge/data/ratchet.txt`, and the spec's examples to CommonMark's html less
the divergences `judge/data/spec_diverge.txt` lists.

- **The corpora:** adversarial and dialect shapes; `unit_cases`, every input
  of chat-markdown's Zig unit tests (where the dialect came from); CommonMark's
  and GFM's examples (`spec_agree`), and GFM's table examples
  (`spec_tables`; both CC BY-SA 4.0: `judge/data/SPEC-LICENSE`);
  pinned departures from CommonMark; and the hostile shapes the judge
  generates itself.
- **It prints counts and failing case ids, never a case's text**, so it can
  judge a private corpus of real messages.

```
zig build test                         # roc test package/main.roc, then the judge
zig build judge -- --also <gold.jsonl> # the judge, with a private corpus too
shale tools/verify.shale               # every check, the planted faults, a checklist
```

The Roc is pinned (`roc-version`): `roc` on the PATH, or `-Droc=<path>`
(showell/roc-apps release `toolchain-2026-10-27` carries it).

## The REPL

`zig build repl` renders markdown as you type it: each block's html, its
work units and its hostility verdict (`Renderable`, or `TooMuchFormatting`
with the words the chat refuses the message with). It calls the package
through the judge's seam (`judge/answers.roc`), so it shows what the judge
holds. The program is `judge/repl.zig`.

- **A block** is the lines you type, each with its newline, up to an empty
  line. A block with empty lines inside (a loose list, a fence) begins with
  an empty line, and two empty lines in a row end it. `:load PATH` takes a
  file's bytes exactly. End of input ends the last block and quits.
- **A command** is a line starting with `:` where a block would begin:

  ```
  :mode             the mode now
  :mode chat        Md.render: the chat's, with its budget (the start)
  :mode trusted     Md.render_trusted: docs, no budget
  :mode reflow      Md.render_trusted_reflow: docs, newlines as spaces
  :examples         the canned examples, each named with its caption
  :ex NAME          one example: its source, then its answer
  :load PATH        a file's bytes, exactly (PATH from the repo's root)
  :help             the commands
  :quit             quit (so does end of input)
  ```

- **Piped, it is plain:** no banner, no prompts, a mode switch silent, and a
  command that fails stops the run (exit 1).

  ```
  $ printf '**hi**\n\n' | zig build repl
  <p><strong>hi</strong></p>
  work units: 16
  hostility: Renderable
  ```

- **The canned examples** are `judge/data/examples.jsonl`, one
  `{"id", "caption", "md"}` a line: a dense example each of the inline
  styles, the blocks, the hard wraps and the escaping, each caption saying
  where the dialect departs from GitHub's. They are a corpus of the judge, so
  their answers are frozen (`examples.answers.jsonl`); a change that moves
  one is a re-freeze (`--refreeze examples`).
- **Its test** (`judge/repl_check.zig`, in `zig build test`) pipes a table,
  a list and a fence with empty lines inside, every canned example and a
  hostile shape through the REPL in each mode, and holds its output byte for
  byte to the frozen answers.

## The playground

A web page where you type markdown and see it rendered as you type, by the
package itself compiled to WebAssembly: the work units, the hostility
verdict and the mode switch under it, the canned examples in a menu (each
loads into the editor, to change freely), and the HTML source behind a
toggle. It is served at roc.lynrummy.com/markdown/ (for now).

```
zig build playground    # zig-out/playground/: the folder a web server serves
```

The folder is static and fetches nothing from elsewhere: `index.html`,
`app.js`, `md_wasm.js` (the wasm's door), `style.css`, `md.wasm` and
`examples.jsonl` (the judge's corpus, copied). The wasm is
`playground/answer.roc` on `playground/platform/` (a wasm32 host, built by
`build.zig`), linked by the pinned Roc with `--opt=dev`. **Its test**
(`playground/check.zig`, in `zig build test`) runs the built wasm in node,
through the page's own `md_wasm.js`, on every canned example, a table, a
loose list, two fences and a hostile shape in each mode, held byte for byte
to the judge's frozen answers; then runs the page on a stand-in DOM
(`playground/page_check.mjs`).

## Layout

- `package/main.roc`: the package and what it exposes.
- `package/Md.roc`: the render, its modes, the block dispatch and the leaf
  blocks.
- `package/MdList.roc`, `package/MdQuote.roc`: the container blocks, lists
  and quotes, handed the dispatch by `Md`.
- `package/MdTable.roc`: where a table opens, a row's cells and alignments.
- `package/MdFence.roc`: where a code fence opens and closes.
- `package/MdInline.roc`: the inline pass: a line's pieces and code spans.
- `package/MdEmphasis.roc`: the emphasis engine, CommonMark's delimiter stack.
- `package/MdLinks.roc`: `[t](u)` links and autolinks.
- `package/MdMedia.roc`: a member's `<img>` and `<video>`, scanned and
  rebuilt.
- `package/MdHtml.roc`: every tag and attribute the renderer writes; a skin
  edits this alone.
- `package/MdChat.roc`: the chat's own extensions (`MSG_` references, the
  `quote` fence, the fence's nesting cap); a fork without a chat, or with
  another, starts here.
- `package/MdSafety.roc`: the URL and attribute rules: dangerous and
  external hrefs, the media's same-origin rule and attribute allowlist.
- `package/MdText.roc`: lines, escaping and the work budget.
- `package/Ascii.roc`, `package/Bytes.roc`: the byte checks and scans
  (Zig's `std.ascii` and `std.mem`) the rest share.
- `judge/`: the judge (`judge.zig`), its side of the Roc (`roc_host.zig`,
  `answers.roc`, `platform/`) and its data (`data/`: the corpora, their
  frozen answers, the ratchet).
- `playground/`: the web playground: its Roc app and wasm32 platform, the
  page, and its test.
- `tools/verify.shale`: every check in one run, the planted faults too.

The history before this repository is roc-webbox's (`chat/`); it was split
out with `git filter-branch`, so `git log --follow` reaches back through it.
