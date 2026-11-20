# roc-markdown

A markdown renderer written in Roc, for two kinds of text: chat messages
that users type, and documents that you write. A chat message becomes HTML
that is safe to show whatever the user typed, with a hard limit on the work
any one message can cost. A document becomes a page, with heading ids for a
table of contents and a hook for your own fences. It is a Roc package with
no dependencies and no platform, pure functions from bytes to bytes, so any
Roc app can import it. It is the dialect of Gopher Chat (lynrummy.com), and
every answer it gives is frozen and checked case by case
([TESTING.md](TESTING.md)).

The code here was written by AI coding agents (Claude), with human supervision.

**Try it:** [the playground](https://roc.lynrummy.com/markdown/) runs this
package, compiled to WebAssembly, as you type. It has dense examples to edit.

## Chat messages

If you know GitHub's or Zulip's markdown, most of it is what you expect:
paragraphs, headings, lists, quotes, fenced code, pipe tables, `**bold**`,
`*italic*`, `~~strike~~`, `` `code` ``, backslash escapes, links, images and
bare URLs. What a chat adds or changes, on purpose:

- A newline is a line break, as in GitHub comments and Zulip, and inline
  markup pairs within a line.
- Raw HTML shows as text. An `<img>` or `<video>`, or a `![alt](src)`, is
  shown only from the uploads the host names. Any other image is a link.
- A link to another site opens in a new tab. A `javascript:` link shows as
  its source, as text.
- `MSG_plans_3` links to that chat message, and a ```` ```quote ```` fence
  is a quoted message.
- `~one tilde~` is text, so "~5 minutes" stays as written.

Emoji and any script pass through untouched. There are no `:shortcodes:`
and no `@mentions`: the HTML depends only on the message's bytes, never on
who reads it or what else is stored.

## Documents

`Md.render_document` renders your own prose as a page. Chat syntax is off
(`MSG_` is text and ```` ```quote ```` is code), a newline is a space, a
link to another site stays in its tab, and raw HTML and `<img>` or `<video>`
tags stay escaped. It answers `{ html, headings }`: each heading has an `id`
made from its text (`whats-a-sighting`, then `whats-a-sighting-2`), and
`headings` lists `{ level, id, text }` for a table of contents.

A document reads more of CommonMark than a chat does, because a page's prose
isn't a message: rules (`---`), indented code, tab stops, `<https://...>`
links, a link's title and `<a b>` destination, and a label that holds an
image (`[![a](i.png)](/x)`). A table keeps every cell, and `a@b.c` stays
text. [COMMONMARK.md](COMMONMARK.md) has each rule.

The `images` option says what `![alt](src)` becomes, and it has no default.
`Shown` is an `<img>` from any src a browser wouldn't run, relative paths and
other sites included, since the prose is your own. `AsLinks` is a link to the
src. A chat's images are neither: they follow its `uploads` rule.

The one way in for your own HTML is the `fence` option, a function from
`{ tag, args, body }` to `Html(bytes)` or `Pass`. For a ```` ```widget sky ````
fence the tag is `widget` and the args are `sky`. `Html` goes out unescaped,
which is why the hook exists only here, and `Pass` renders ordinary code with
`class="language-<tag>"`.

```roc
fence = |{ tag, args, body }|
	if tag == Str.to_utf8("widget") {
		Html(iframe_for(args))
	} else if tag == Str.to_utf8("dot") {
		Html(svg_of(body))
	} else {
		Pass
	}

page = Md.render_document(chapter, { fence: fence, images: Shown })
```

## Where it differs from CommonMark

[COMMONMARK.md](COMMONMARK.md) has the exact rules: each place either mode
departs from CommonMark and GFM, with the reason, and how many of the spec's
examples each mode matches. Neither mode reads link reference definitions,
setext headings, raw HTML or entity references.

## What it guarantees

- **Safe output, whatever the input.** Every byte a user wrote is escaped,
  except the markup the dialect itself writes. What it won't run, it shows:
  a `javascript:` link (or `![alt](src)`) is no link at all but its own
  source, as text, as raw HTML is. A user's image or video tag, or a
  markdown `![alt](src)`, is rebuilt from an allowlist of attributes, and
  only when it points at the host's uploads, never at another of the
  app's own routes or another site.
- **The host names its uploads, in each render's options** (`Md.Options`):
  where its files live is the host's to say, not the renderer's. The
  renderer judges the src as a URL (same origin, no `..`, no encoded `/`),
  then asks the host's rule. There is no default: `Md.no_uploads` renders
  no media.
- **The host may color its code blocks, in the same options** (`code`): the
  hook is given a block's language and body and answers `Colored(html)`,
  which goes inside the renderer's own `<pre><code class="language-…">`, or
  `Plain`, the renderer's escape. A quote-reply is never offered. The HTML
  is the host's to make safe, as a document's fence hook's is. There is no
  default: `Md.plain_code` colors nothing.
- **A bounded cost.** Rendering is linear in the message, and every step is
  charged to a work budget sized by its length. A message built to blow it up
  (thousands of nested brackets, a table thousands of columns wide) is
  refused up front: `Md.hostility` says so before you render, and a chat
  refuses it whole (the playground's `hostile` example). Trusted text has
  no budget: its caller decides.
- **A stable dialect.** The same input gives the same HTML from one release
  to the next unless a change is deliberate. The answers are frozen, and a
  change that moves one names it ([TESTING.md](TESTING.md)).

## Use

The package is imported by path. The pinned Roc compiler (`roc-version`) takes
a local package that way:

```roc
app [main!] {
	pf: platform "...",
	md: "../roc-markdown/package/main.roc",
}

import md.Md
```

Every chat render takes the host's options, `{ uploads, code }`: a rule
saying which same-origin paths are its uploads, and a hook for its code
blocks' bodies.

```roc
options = { uploads: Md.uploads_under(Str.to_utf8("/user_uploads/")), code: Md.plain_code }
html = Md.render(message, options)
```

| Function | What it does |
|---|---|
| `Md.render : List(U8), Md.Options -> List(U8)` | a chat message to HTML, within the budget |
| `Md.hostility : List(U8), Md.Options -> [Renderable, TooMuchFormatting]` | whether a message is within the budget, before you render it |
| `Md.work_units : List(U8), Md.Options -> U64` | what a render costs |
| `Md.render_trusted : List(U8), Md.Options -> List(U8)` | your own docs, no budget |
| `Md.render_trusted_reflow : List(U8), Md.Options -> List(U8)` | the same, a newline as a space |
| `Md.render_document : List(U8), Md.DocumentOptions -> MdDocument.Page` | a page of a book, with a hook for its fences and a choice about its images (Documents, above) |
| `Md.uploads_under : List(U8) -> (List(U8) -> Bool)` | the rule of one uploads folder: every path under it |
| `Md.no_uploads : List(U8) -> Bool` | the rule of a host with no uploads |
| `Md.escape : List(U8) -> List(U8)` | text made safe for HTML, the renderer's own escape, for your pages |

`MdFence`, `MdMedia` and `MdTable` are exposed for a host that reads one of
those blocks outside a render, so it reads the renderer's own grammar: a
fence's open and close (a feed of code excerpts), a stored `<img>` rebuilt
by the media rule (`MdMedia.rebuild`, a feed of images), a table row's cells.

## Changing it

The package is meant to be forked, and the likely changes each have one home:
- **The HTML it writes** (tags, classes, attributes for your own styling):
  `package/MdHtml.roc`.
- **The safety rules** (which links and media are allowed): `package/MdSafety.roc`.
- **The chat's own syntax** (`MSG_` links, the quote fence): `package/MdChat.roc`.
  A non-chat app removes it, and another chat adds its own, such as
  `@mentions`, there.

## Who uses it

- **[roc-chat](https://github.com/showell/roc-chat)**, the Roc chat: its
  pages render every message with this package, checked out beside it. It
  runs at chat.lynrummy.com, and it isn't in production yet: lynrummy.com's
  chat is still the Zig one.
- **The Safari Ride book** at roc.lynrummy.com/tutorial/: its pages are
  rendered in document mode, from roc-apps' book builder.

## Another Roc markdown library

[grayrest/roc-markdown](https://github.com/grayrest/roc-markdown), by Karl
Guertin, is a different tool for a different job, and a good one. It parses
CommonMark 0.31.2 with the GFM extensions (its spec tests pass all but a
handful of the spec's examples), and it gives you a typed tree of blocks and
inlines, each with its place in the source, built for an editor, with HTML
output beside it. Reach for it when you want full CommonMark, a tree to
walk, or source positions.

Reach for this package when you're rendering user messages in a chat or
anything like one: bytes in, safe HTML out, a dialect people already type,
and a bound on each message's total work that lets a host refuse a message
built to be expensive (`Md.hostility`). For your own prose, its document mode
(`Md.render_document`, above) turns the chat syntax off and reads more
CommonMark: rules, indented code, `<https://...>` links, link titles, and
heading ids for a table of contents. It builds no tree.

The two agree closely on what a link may point to: the same refused schemes
and the same browser-style cleanup of a URL. They differ in what a refusal
looks like. Here a refused link shows its source as text; there it keeps
its label and drops the link.

## Status

- **Its history:** it began as a port of the chat's original renderer, in Zig,
  and has diverged from it on purpose since 2026-10-29.
- **The Roc compiler is pinned** to a nightly, as Roc has no stable release
  yet. A newer nightly may need small changes.

How it is tested, and the tools for working on it, are in
[TESTING.md](TESTING.md).

## License

[UPL-1.0](LICENSE), the license Roc itself uses.
