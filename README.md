# roc-markdown

A markdown renderer for chat, written in Roc: messages to HTML, safe to show
whatever a user typed, with a hard limit on the work any one message can
cost. It is a Roc package with no dependencies and no platform, pure
functions from bytes to bytes, so any Roc app can import it. It is the
dialect of Gopher Chat (lynrummy.com), and it is held, case by case, to
frozen answers for 314 of CommonMark's and GFM's spec examples (TESTING.md
says how they were chosen), about a thousand hostile inputs, and ten
thousand real chat messages.

**Try it:** [the playground](https://roc.lynrummy.com/markdown/) runs this
package, compiled to WebAssembly, as you type. It has dense examples to edit.

## The dialect at a glance

If you know GitHub's or Zulip's markdown, most of it is what you expect:
paragraphs, headings, lists, quotes, fenced code, pipe tables, `**bold**`,
`*italic*`, `~~strike~~`, `` `code` ``, backslash escapes, links, images and
bare URLs. Where it differs:

| | roc-markdown | GitHub |
|---|---|---|
| A newline inside a paragraph | a line break (as in GitHub comments and Zulip) | a space, in documents |
| `**bold` across a line break `**` | stays literal: inline markup pairs within a line | pairs |
| Raw HTML | escaped, shown as text | a safe subset rendered |
| `<img>`, `<video>` | only the uploads the host names, rebuilt from safe attributes | sanitized |
| A link to another site | opens in a new tab | same tab |
| `[click](javascript:alert(1))` | its source, shown as text | the label, its href dropped |
| `MSG_plans_3`, `MSG_Cobblestone.plans_3` | a link to that chat message (a topic's, on its own page; a channel's topic's) | text |
| ```` ```quote ```` | a quoted message, shown as written | a code block |
| `![alt](src)` | an image only from the uploads the host names; any other src becomes a link | an image from anywhere |
| `~one tilde~` (`~~two~~` strikes, as on GitHub) | text, so "~5 minutes" stays as written | strikes too |

Emoji and any script pass through untouched. There are no `:shortcodes:`
and no `@mentions`: the HTML depends only on the message's bytes, never on
who reads it or what else is stored.

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

Every render takes the host's options, `{ uploads }`: a rule saying which
same-origin paths are its uploads.

```roc
options = { uploads: Md.uploads_under(Str.to_utf8("/user_uploads/")) }
html = Md.render(message, options)
```

| Function | What it does |
|---|---|
| `Md.render : List(U8), Md.Options -> List(U8)` | a chat message to HTML, within the budget |
| `Md.hostility : List(U8), Md.Options -> [Renderable, TooMuchFormatting]` | whether a message is within the budget, before you render it |
| `Md.work_units : List(U8), Md.Options -> U64` | what a render costs |
| `Md.render_trusted : List(U8), Md.Options -> List(U8)` | your own docs, no budget |
| `Md.render_trusted_reflow : List(U8), Md.Options -> List(U8)` | the same, a newline as a space |
| `Md.render_document : List(U8), Md.DocumentOptions -> MdDocument.Rendered` | a page of a book, with a hook for its fences and a choice about its images (below) |
| `Md.uploads_under : List(U8) -> (List(U8) -> Bool)` | the rule of one uploads folder: every path under it |
| `Md.no_uploads : List(U8) -> Bool` | the rule of a host with no uploads |
| `Md.escape : List(U8) -> List(U8)` | text made safe for HTML, the renderer's own escape, for your pages |

`MdFence`, `MdMedia` and `MdTable` are exposed for a host that reads one of
those blocks outside a render, so it reads the renderer's own grammar: a
fence's open and close (a feed of code excerpts), a stored `<img>` rebuilt
by the media rule (`MdMedia.rebuild`, a feed of images), a table row's cells.

## Documents

`Md.render_document` renders your own prose as a page. Chat syntax is off
(`MSG_` is text and ```` ```quote ```` is code), a newline is a space, a
link to another site stays in its tab, and raw HTML and `<img>` or `<video>`
tags stay escaped. It answers `{ html, headings }`: each heading has an `id`
made from its text (`whats-a-sighting`, then `whats-a-sighting-2`), and
`headings` lists `{ level, id, text }` for a table of contents.

A document reads some markdown a chat doesn't, because a chat's answers are
frozen and a page's prose isn't a message:

- `---`, `***` and `___` are a rule, `<hr>`. There are no setext headings, so
  `---` under a line of text ends that paragraph and is a rule.
- A line indented four columns (a tab is up to four) is code, as in CommonMark:
  it can't interrupt a paragraph, and in a list the four columns count from the
  item's content. A tab in any indent, or after a list's or a quote's marker,
  counts as the columns it reaches.
- `<http://...>` and `<https://...>` are links.
- A link's label ends at its balancing `]`, so `[![a](i.png)](/x)` is a linked
  image, and nothing in a label becomes a second link.
- A link reads a title and `<a b>`: `[a](<b c> "t")`.
- A table's row keeps every cell, past the header's width too, where GFM and a
  chat drop what's over. Losing the author's text is never right on a page.
- `a@b.c` is text, since a page's `a@b.c` is rarely an address. A written
  `[a](mailto:b@c.d)` stays a link.

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

## Changing it

The package is meant to be forked, and the likely changes each have one home:
- **The HTML it writes** (tags, classes, attributes for your own styling):
  `package/MdHtml.roc`.
- **The safety rules** (which links and media are allowed): `package/MdSafety.roc`.
- **The chat's own syntax** (`MSG_` links, the quote fence): `package/MdChat.roc`.
  A non-chat app removes it, and another chat adds its own, such as
  `@mentions`, there.

## Status

- **In use:** it renders Gopher Chat's new Roc server (chat.lynrummy.com).
- **Its history:** it began as a port of the chat's original renderer, in Zig,
  and has diverged from it on purpose since 2026-10-29.
- **The Roc compiler is pinned** to a nightly, as Roc has no stable release
  yet. A newer nightly may need small changes.

How it is tested, and the tools for working on it, are in
[TESTING.md](TESTING.md).

## License

[UPL-1.0](LICENSE), the license Roc itself uses.
