# Testing roc-markdown

**The renderer is the definition of the dialect, and frozen answers are its
judge.** Every case of every corpus holds its answers byte for byte: the
chat's render's HTML, its work units, its hostility verdict, and both
trusted renders. An answer changes only by an explicit re-freeze, which names
every case that moved. Each corpus's pass count is held to a ratchet, which
only rises.

```
zig build test                          # roc test, then the judge, the REPL's and the playground's tests
zig build judge -- --also <gold.jsonl>  # the judge, with a private corpus too
shale tools/verify.shale                # every check above, the planted faults, a PASS/FAIL checklist
```

The Roc is pinned (`roc-version`): `roc` on the PATH, or `-Droc=<path>`. The
showell/roc-apps release `toolchain-2026-10-27` carries it. Zig is 0.17.

## The corpora

They're in `judge/data/`, each listed in `corpora.txt` with its answers
beside it (`<name>.answers.jsonl`):

- **adversarial**, **dialect** and **pinned:** shapes chosen by hand, and
  the dialect's deliberate departures from CommonMark.
- **unit_cases:** every input of the original Zig renderer's unit tests,
  where the dialect came from.
- **spec_agree:** CommonMark's and GFM's spec examples, held to the spec's
  HTML, less the deliberate divergences `spec_diverge.txt` lists. A check
  fails both ways: a listed case that now matches is stale and must come off
  the list.
- **spec_tables, spec_strike, spec_escapes, spec_images:** GFM's table and
  strikethrough examples, and CommonMark's backslash-escape and image
  examples, every one of their sections, held to the spec's HTML as
  spec_agree is. The spec corpora are CC BY-SA 4.0 (`SPEC-LICENSE`).
- **examples:** the playground's canned examples, frozen so a change that
  moves one fails loudly.
- **hostile:** shapes the judge generates itself at sizes from 1 to 8,191
  (deep nesting, long delimiter runs, wide tables). Their answers are hashed
  to keep the file small. Verify also holds their work units linear.

**A private corpus,** such as gold, the chat's ten thousand real messages, is
passed with `--also` and never leaves the machine it lives on. **The judge
prints counts and failing case ids, never a case's text,** so it can judge
messages nobody else should read.

## Re-freezing

`zig build judge -- --refreeze LABEL` rewrites one corpus's answers and
names each case that changed. Do it only when a change is deliberate, and
explain every moved case in the commit. For a private corpus, describe what
moved without quoting it: "four tables, one link with parens".

## Verify

`tools/verify.shale` runs everything in one go and prints a checklist:
- the build and tests;
- each corpus's exact count;
- the hostile shapes' linearity;
- the budget's refusals;
- the REPL's and the playground's tests;
- both formatters;
- roc-chat's tests against this package;
- gold, when it's on the machine (a `SKIP` elsewhere, the only skip
  allowed).

**Planted faults:** a changed byte in a frozen answer, a wrong hostile hash,
and a stale divergence. Each is made in a scratch copy and must turn the
judge red for its own reason.

## The REPL

`zig build repl` renders markdown typed at a prompt, or piped in:

```
$ printf '**hi**\n\n' | zig build repl
<p><strong>hi</strong></p>
work units: 16
hostility: Renderable
```

- **Blocks:** a block ends at an empty line. One with empty lines inside
  begins with an empty line and ends at two.
- **Commands:** `:mode chat|trusted|reflow`, `:examples`, `:ex NAME`,
  `:load PATH`, `:help` and `:quit`.
- **Piped:** no banner and no prompts, and a failed command exits 1.

Its test (`judge/repl_check.zig`) holds its output to the frozen answers.

## The playground

```
zig build playground    # zig-out/playground/: a static folder to serve
```

The package compiled to wasm32 (`playground/answer.roc` on
`playground/platform/`, a freestanding wasm host), with a page, its script and
style, and the canned examples. Its test (`playground/check.zig`) runs the
built wasm in node, through the page's own `md_wasm.js`, and holds it byte
for byte to the frozen answers in all three modes. It then loads the page on
a stand-in DOM (`playground/page_check.mjs`). It's served at
roc.lynrummy.com/markdown/, through roc-apps' static site.

**What the box publishes:** `zig-out/playground/*` at the site's `/markdown/`,
and `zig-out/user_uploads/sample.png` at the site root's
`/user_uploads/sample.png`: the `safety` example's image is an upload, as
every image a message shows must be (`MdChat.uploads_prefix`).

## Layout

| Path | What |
|---|---|
| `package/main.roc` | the package and what it exposes |
| `package/Md.roc` | the API, the modes, the block dispatch and the leaf blocks |
| `package/MdList.roc`, `MdQuote.roc` | the container blocks, handed the dispatch by `Md` |
| `package/MdTable.roc`, `MdFence.roc` | tables, and code fences |
| `package/MdInline.roc` | the inline pass: a line's pieces and code spans |
| `package/MdEmphasis.roc` | the emphasis engine, CommonMark's delimiter stack |
| `package/MdLinks.roc` | links and autolinks |
| `package/MdMedia.roc` | a user's `<img>` and `<video>`, scanned and rebuilt |
| `package/MdHtml.roc` | every tag and attribute the renderer writes |
| `package/MdSafety.roc` | the URL and attribute rules |
| `package/MdChat.roc` | the chat's own extensions |
| `package/MdText.roc` | lines, escaping and the work budget |
| `package/Ascii.roc`, `Bytes.roc` | the byte checks and scans the rest share |
| `judge/` | the judge, its side of the Roc, the REPL, and `data/` |
| `playground/` | the playground: its Roc app, wasm32 platform, page and test |
| `tools/verify.shale` | every check in one run |

The history before this repository is roc-webbox's (`chat/`). It was split
out with `git filter-branch`, so `git log --follow` reaches back through it.
