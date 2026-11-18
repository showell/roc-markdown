# How roc-markdown differs from CommonMark and GFM

These are the exact rules where roc-markdown parts from
[CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/) and
[GFM](https://github.github.com/gfm/). Everything not listed here follows
the spec. Each line says what the spec does, what roc-markdown does, why, and
which mode it applies to: **chat** (`Md.render` and its trusted forms),
**document** (`Md.render_document`), or **both**. The README says what the
two modes are for.

## How closely it matches

The judge holds 314 spec examples, chosen like this. From the sections the
dialect covers (emphasis, code spans, links, lists, block quotes, ATX
headings, fenced code and GFM's autolinks), 401 examples were considered and
269 kept: an example was left out when its markdown held something the
dialect had no rule for when they were chosen (`\`, `&`, `<`, `![`, `]:`,
`"`, a tab, or a 4-space indent). Added to those are every example of GFM's
tables (8) and strikethrough (2), and of CommonMark's backslash escapes (13)
and images (22). Since whole areas were left out (entities, raw HTML,
indented code, tabs), these numbers say how close the covered sections are,
not how close the whole spec is.

Compared as the judge compares them, after the same normalization:

- **A chat render matches 263 of the 314.** Each of the other 51 is listed,
  with its reason, in `judge/data/spec_diverge.txt`, and the judge fails if
  that list is out of date.
- **A document render matches 245.** The count is 267 when whitespace
  differences are ignored, since a document writes a space where CommonMark
  writes a line break inside a paragraph, and a browser shows both the same.
  With heading ids also set aside, it is 282. The 32 left are the departures
  below. These document numbers were measured once and are not held by a
  gate.

## Blocks

| CommonMark or GFM | roc-markdown | Why | Mode |
|---|---|---|---|
| A line under a paragraph made of `===` or `---` turns it into a heading (setext). | There are no setext headings. `---` under text ends the paragraph and is a rule in a document, or text in a chat. | One way to write a heading. A line of dashes under a sentence is rarely meant as a heading. | both |
| `---`, `***` and `___` are a thematic break, `<hr>`. | They are a rule in a document and text in a chat. | In a chat, a line of dashes is usually just dashes. | chat |
| A line indented four spaces is indented code. | It is code in a document. In a chat it is a paragraph: code goes in a fence. | Chat messages are often indented by accident. | chat |
| A tab in an indent counts to the next tab stop. | It does in a document. A chat counts spaces alone, so a tab adds no indent. | A chat's indent is the spaces typed. | chat |
| Raw HTML blocks and inline tags pass through. | Escaped and shown as text. In a chat, an `<img>` or `<video>` that points at the host's uploads is rebuilt from safe attributes. | The output is safe whatever the input. | both |
| GFM drops a table row's cells past the header's width. | A chat drops them, as GFM does. A document keeps them. | Losing the author's text is never right on a page. | document |
| Link reference definitions (`[foo]: /url`) and the links that use them (`[foo]`, `[foo][]`, `[x][foo]`). | Not read. The definition is a paragraph of text, and `[foo]` is text. | A link is written where it stands: a message stands alone, and so does a page's every paragraph. | both |
| A fence opens with any run of three or more backticks or tildes. | A run of 3 to 10. A longer run is text. | It bounds the chat's quote-reply nesting. | both |
| A fence is code. | In a chat, a ```` ```quote ```` fence is a quoted message, shown as written. | The chat's quote-reply. | chat |

## Inlines

| CommonMark or GFM | roc-markdown | Why | Mode |
|---|---|---|---|
| A line break inside a paragraph is soft: a newline, which a browser shows as a space. | In a chat it is a `<br>`. In a document it is a space. | Chat users expect what they typed (GitHub comments and Zulip do the same). | chat |
| Emphasis, strong, strikethrough and code spans may cross a line break. | In a chat each line's markup pairs within that line, so `**a` then `b**` stays literal. A document reflows first, so spans cross lines. | A chat line is read as written, and a stray `*` can't swallow the next line. | chat |
| A backslash at a line's end is a hard break. | A `<br>`, as in the spec. A chat already breaks every line, so the backslash adds nothing. | | both |
| Two spaces at a line's end are a hard break. | Not a break: a document joins the lines with a space. | Invisible markup. Write a backslash instead. | document |
| Left- and right-flanking count Unicode whitespace and punctuation. | Only ASCII whitespace and punctuation count; any other character counts as a letter. | Simpler, and the same answer for nearly all text. | both |
| `~one~` strikes in GFM. | Only `~~two~~` strikes. One tilde is text. | So "~5 minutes" stays as written. | both |
| Entity and numeric character references (`&copy;`, `&#65;`) are decoded. | They are text: `&` is always escaped, so `&copy;` shows as written. | One escape for every byte, and no table of names. | both |
| A code span binds tighter than a link's brackets, so `` [a `b](c)` `` is no link. | **A known gap:** the link wins (cm/342, cm/525). The fix has to keep the scan linear. | | both |

## Links and images

| CommonMark or GFM | roc-markdown | Why | Mode |
|---|---|---|---|
| A label ends at the `]` that balances its `[`, and the innermost link wins. | In a chat, a label ends at its first `]`. A document's label ends at its balancing `]`, but then nothing inside it becomes a second link: the outer link wins. | A chat's label is plain. A page may link an image, `[![a](i.png)](/x)`. Either way the cost stays linear. | both |
| A destination ends at a space, `<…>` holds one, and a title may follow. | A document follows the spec. A chat reads the whole destination as the href, spaces and quotes included. | A chat's link is the text between the parens. | chat |
| A link may point anywhere. | A `javascript:`, `data:` or other dangerous destination is no link: its source shows as text. | Safety: what a browser would run, the reader sees. | both |
| A link to another site opens in the same tab. | In a chat it opens in a new tab. | So a reader keeps their place in the chat. | chat |
| An image may come from any src. | In a chat, an image is shown only from the host's uploads (`Md.Options`), and any other src becomes a link. In a document, the `images` option shows any safe src or makes every image a link. | The host decides where a chat's media comes from. | both |
| An image's alt is its label's plain text, with nested links and images reduced to their text. | A nested link or image in an alt stays as its source text. | It bounds the cost: an alt is read once, however its brackets nest. | document |
| `<scheme:…>` is an autolink. | A document links `<http://…>` and `<https://…>` only. A chat has none, since `<` starts raw HTML, which is escaped. | Only the schemes a reader can follow. | both |
| A `\` in an autolink's URL is percent-encoded (`%5C`). | **A known gap:** it stays a `\` in the href (cm/20). | | document |
| GFM links bare `http://`, `https://`, `www.`, `ftp://` and email addresses. | A chat links all but `ftp://`. A document leaves an email as text. | `ftp://` is gone from browsers. On a page, `a@b.c` is rarely an address; write `[a](mailto:b@c.d)`. | both |

## Only in a chat

- `MSG_plans_3` and `MSG_<channel>.plans_3` link to that chat message
  (package/MdChat.roc).
- No `:shortcodes:` and no `@mentions`: the HTML depends only on the
  message's bytes.
- A message whose rendering would cost too much is refused whole
  (`Md.hostility`), rather than rendered.

## Only in a document

- Each heading has an `id` made from its text, and the page lists its
  headings (`MdDocument.Page`).
- The `fence` hook turns a fence into the caller's own HTML.
