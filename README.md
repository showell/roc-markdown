# roc-markdown

A markdown renderer for chat, written in Roc: messages to HTML, safe to show
whatever a user typed, with a hard limit on the work any one message can
cost. It is a Roc package with no dependencies and no platform, pure
functions from bytes to bytes, so any Roc app can import it. It is the
dialect of Gopher Chat (lynrummy.com), and it is held, case by case, to
frozen answers for CommonMark's and GFM's spec examples, thousands of hostile
inputs, and ten thousand real chat messages.

**Try it:** [the playground](https://roc.lynrummy.com/markdown/) runs this
package, compiled to WebAssembly, as you type. It has dense examples to edit.

## The dialect at a glance

If you know GitHub's or Zulip's markdown, most of it is what you expect:
paragraphs, headings, lists, quotes, fenced code, pipe tables, `**bold**`,
`*italic*`, `` `code` ``, links and bare URLs. Where it differs:

| | roc-markdown | GitHub |
|---|---|---|
| A newline inside a paragraph | a line break (as in GitHub comments and Zulip) | a space, in documents |
| `**bold` across a line break `**` | stays literal: inline markup pairs within a line | pairs |
| Raw HTML | escaped, shown as text | a safe subset rendered |
| `<img>`, `<video>` | only the chat's uploads (`/user_uploads/…`), rebuilt from safe attributes | sanitized |
| A link to another site | opens in a new tab | same tab |
| `MSG_plans_3` | a link to that chat message | text |
| ```` ```quote ```` | a quoted message, shown as written | a code block |
| `~~strike~~` | two tildes only: `~5 minutes` stays as written | one or two |
| `![alt](src)` | an image only from the chat's uploads; any other src is a link | any image |
| `\` at a line's end | dropped: every newline breaks already | a line break |

Emoji and any script pass through untouched. There are no `:shortcodes:`
and no `@mentions`: the HTML depends only on the message's bytes, never on
who reads it or what else is stored.

## What it guarantees

- **Safe output, whatever the input.** Every byte a user wrote is escaped,
  except the markup the dialect itself writes. A `javascript:` link loses its
  href. A user's image or video tag is rebuilt from an allowlist of
  attributes, and only when it points at the chat's uploads
  (`/user_uploads/`, set in `package/MdChat.roc`), never another of the
  app's own routes; a markdown image `![alt](src)` follows the same rule,
  and is a link otherwise.
- **A bounded cost.** Rendering is linear in the message, and every step is
  charged to a work budget sized by its length. A message built to blow it up
  (thousands of nested brackets, a table thousands of columns wide) is
  refused up front: `Md.hostility` says so before you render.
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

| Function | What it does |
|---|---|
| `Md.render : List(U8) -> List(U8)` | a chat message to HTML, within the budget |
| `Md.hostility : List(U8) -> [Renderable, TooMuchFormatting]` | whether a message is within the budget, before you render it |
| `Md.work_units : List(U8) -> U64` | what a render costs |
| `Md.render_trusted : List(U8) -> List(U8)` | your own docs, no budget |
| `Md.render_trusted_reflow : List(U8) -> List(U8)` | the same, a newline as a space |

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
