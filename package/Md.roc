## **THE CHAT'S MARKDOWN**, the dialect's definition: a member's message to
## HTML. GFM-style paragraphs with hard wraps, ATX headings, fenced code
## (with the chat's `quote` fence of a reply, MdChat), lists (MdList),
## blockquotes (MdQuote), GFM's pipe tables (MdTable), and the raw HTML
## block, which is escaped but for a same-origin `<img>` or `<video>`
## (MdMedia); each line's inline content is MdInline's. Every tag is
## MdHtml's. Pure.
##
## **THIS MODULE IS THE API, THE MODES AND THE DISPATCH**, and the leaf
## blocks. The containers, lists and quotes, are modules of their own; their
## content is blocks again, so `blocks_onto` hands each the recursion
## (`nested`, at one level deeper, in this render's wrap) and the block
## starts it asks about (`is_block_start`), rather than each importing Md,
## a cycle. Each block's grammar (where a fence or a table opens) is its own
## module's (MdFence, MdTable). A new block kind is a branch of
## `blocks_onto`, and a line of `is_block_start` (and of `paragraph_onto`'s
## stop) when it interrupts a paragraph.
##
## **THE PARSER IS THE JUDGE OF HOSTILITY**: a render charges its work to a
## budget (MdText), checked at each block line and each inline step, and a
## message that blows it renders as `malformed_html` and is refused at
## POST (`hostility`). There is no second model of "too much" to drift from
## the parser. The judge (judge/judge.zig) holds every corpus case to its
## frozen html and `work_units`.
##
## A block nested past `max_block_depth` renders as one flat paragraph, so
## no message recurses deeper than that; every walk along a line is a loop.
import Ascii
import Bytes
import MdText
import MdChat
import MdDocument
import MdFence
import MdHtml
import MdInline
import MdList
import MdMedia
import MdQuote
import MdSafety
import MdTable

Md := [].{

	## **WHAT THE HOST TELLS A RENDER**: which same-origin paths are its
	## uploads, the only places a member's `<img>`, `<video>` or
	## `![alt](src)` may load from (MdSafety.is_upload_url). Where a host
	## keeps its files is the host's to say: the renderer judges a src as a
	## URL, and asks this rule of one that passes. There is no default; a
	## host with no uploads passes `no_uploads`.
	Options : { uploads : MdSafety.Uploads }

	## The rule of one uploads folder: every path under `prefix`.
	uploads_under : List(U8) -> MdSafety.Uploads
	uploads_under = |prefix| MdSafety.under(prefix)

	## The rule of a host with no uploads: every member's media is text.
	no_uploads : MdSafety.Uploads
	no_uploads = |_| Bool.False

	## A member's message, with its budget; a hostile one
	## is `malformed_html`.
	render : List(U8), Md.Options -> List(U8)
	render = |md, { uploads }| rendered(md, { wrap: HardWrap, budget: MdText.for_input(md), uploads, dialect: Chat })

	## Server-owned text, never a request's, with no
	## limit on its work. The depth cap and the escaping still hold.
	render_trusted : List(U8), Md.Options -> List(U8)
	render_trusted = |md, { uploads }| rendered(md, { wrap: HardWrap, budget: MdText.unlimited, uploads, dialect: Chat })

	## Server-owned prose, whose source line
	## wraps join with a space rather than a `<br>`, so a span may cross one
	## and the text rewraps to the reader's width.
	render_trusted_reflow : List(U8), Md.Options -> List(U8)
	render_trusted_reflow = |md, { uploads }| rendered(md, { wrap: Reflow, budget: MdText.unlimited, uploads, dialect: Chat })

	## How a document's render treats a fenced block it doesn't know.
	DocumentOptions : { fence : MdDocument.FenceHook }

	## Server-owned prose as a page of a book. It has no budget and no chat
	## syntax, a newline is a space, a link to another site stays in its tab,
	## raw HTML is escaped, and each heading has an id. The hook is the one
	## way in for HTML of the caller's own.
	render_document : List(U8), Md.DocumentOptions -> MdDocument.Rendered
	render_document = |md, { fence }| MdDocument.named(rendered(md, { wrap: Reflow, budget: MdText.unlimited, uploads: no_uploads, dialect: Document(fence) }))

	## Text made safe for HTML, an element's content or an attribute's value
	## (either quote): `&`, `<`, `>`, `"` and `'` as entities, every other
	## byte as it is. The renderer's own escape, for a host's pages to share.
	escape : List(U8) -> List(U8)
	escape = |text| MdText.escape_onto([], text)

	## The work a render of `md` costs, unlimited, the
	## measure the budget caps.
	work_units : List(U8), Md.Options -> U64
	work_units = |md, { uploads }| match run(md, { wrap: HardWrap, budget: MdText.unlimited, uploads, dialect: Chat }) {
		Ok(done) => done.budget.spent
		Err(Hostile) => crash "Md.work_units: an unlimited budget blown"
	}

	## Whether `md` would blow its budget, so a POST
	## refuses it. One render in good faith with the real budget.
	hostility : List(U8), Md.Options -> [Renderable, TooMuchFormatting]
	hostility = |md, { uploads }| match run(md, { wrap: HardWrap, budget: MdText.for_input(md), uploads, dialect: Chat }) {
		Ok(_) => Renderable
		Err(Hostile) => TooMuchFormatting
	}

	## The words a refused POST says.
	too_much_formatting : Str
	too_much_formatting = "too much markdown formatting"

	## What a hostile message renders as: an escaped paragraph, the client
	## free to style `.md-malformed`.
	malformed_html : List(U8)
	malformed_html = MdHtml.malformed
}

## A chat's syntax, or a document's, with the hook its fences go through.
Dialect : [Chat, Document(MdDocument.FenceHook)]

## The one seed every render grows from: `md`'s blocks from the top, as a
## document's, in `wrap` and against `budget`.
run : List(U8), { wrap : [HardWrap, Reflow], budget : MdText.Budget, uploads : MdSafety.Uploads, dialect : Dialect } -> Try(MdText.Rendered, [Hostile])
run = |md, { wrap, budget, uploads, dialect }| blocks_onto({
	out: [],
	md,
	spacing: Loose,
	depth: 0,
	wrap,
	budget,
	uploads,
	dialect,
})

rendered : List(U8), { wrap : [HardWrap, Reflow], budget : MdText.Budget, uploads : MdSafety.Uploads, dialect : Dialect } -> List(U8)
rendered = |md, { wrap, budget, uploads, dialect }| match run(md, { wrap, budget, uploads, dialect }) {
	Ok(done) => done.out
	Err(Hostile) => Md.malformed_html
}

## Quotes and lists nest at most this deep;
## past it, the rest renders as one paragraph. Ordinary conversation never
## nests past about 10 (Steve, 2026-06-19).
max_block_depth : U64
max_block_depth = 16

## The block dispatcher: `md`'s blocks onto
## `out`. `Tight` spacing is a tight list item's content: its paragraphs have no
## `<p>`, and its blocks are joined by one newline. One unit a block line,
## and a check, where the previous line's inline charges are noticed too.
blocks_onto : {
	out : List(U8),
	md : List(U8),
	spacing : [Tight, Loose],
	depth : U64,
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : Dialect,
} -> Try(MdText.Rendered, [Hostile])
blocks_onto = |
	{
		out,
		md,
		spacing,
		depth,
		wrap,
		budget,
		uploads,
		dialect,
	},
|
	if depth > max_block_depth {
		start = if (out != [] and out.last() != Ok('\n')) out.append('\n') else out
		flat = MdInline.render_onto({
			out: start.concat(MdHtml.p_open),
			text: md,
			refs: inline_refs(dialect),
			budget,
			uploads,
		})?
		Ok({ out: flat.out.concat(MdHtml.p_close), budget: flat.budget })
	} else {
		len = md.len()
		# A container's content is blocks one level deeper, in this render's
		# wrap: the recursion MdList and MdQuote are handed, so they need no
		# import of Md (a cycle) and the depth stays this module's.
		nested = |inner| blocks_onto({
			out: inner.out,
			md: inner.md,
			spacing: inner.spacing,
			depth: depth + 1,
			wrap,
			budget: inner.budget,
			uploads,
			dialect,
		})
		var $out = out
		var $budget = budget
		var $pos = 0
		while $pos < len {
			$budget = MdText.charge($budget, 1)
			if MdText.is_blown($budget) {
				return Err(Hostile)
			} else {
				{}
			}
			eol = MdText.line_end(md, $pos)
			line = MdText.cut(md, { start: $pos, end: eol })
			next = MdText.next_line(md, eol)
			if MdText.is_blank(line) {
				$pos = next
			} else {
				block = block_at(
					tight_sep($out, spacing),
					{
						md,
						pos: $pos,
						line,
						next,
						spacing,
						wrap,
						budget: $budget,
						nested,
						uploads,
						dialect,
					},
				)?
				$out = block.out
				$budget = block.budget
				$pos = block.after
			}
		}
		Ok({ out: $out, budget: $budget })
	}

## The block at `pos` (its line `line`, the line after it at `next`) onto
## `out`, already separated from the block before: the dispatcher's one
## question, its blocks in the order they are asked. A fence, a heading, a
## list and a quote can each interrupt a paragraph, so each is asked first;
## then an HTML block and a table; else a paragraph.
block_at : List(U8),
{
	md : List(U8),
	pos : U64,
	line : List(U8),
	next : U64,
	spacing : [Tight, Loose],
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
	uploads : MdSafety.Uploads,
	dialect : Dialect,
} -> Try(MdText.Block, [Hostile])
block_at = |
	out,
	{
		md,
		pos,
		line,
		next,
		spacing,
		wrap,
		budget,
		nested,
		uploads,
		dialect,
	},
|
	match MdFence.open_at(md, pos) {
		Ok(open) => Ok(fence_onto(out, { md, open, line, budget, dialect }))
		Err(NotAFence) =>
			match atx_heading(line) {
				Ok(h) => heading_onto(out, { level: h.level, content: h.content, after: next, budget, uploads, dialect })
				Err(NotAHeading) =>
					match MdList.list_marker_at(md, pos) {
						Ok(marker) => MdList.list_onto(out, { md, pos, first: marker, budget, nested, is_block_start })
						Err(NotAMarker) =>
							if MdQuote.is_quote_line(line) {
								MdQuote.quote_onto(out, { md, pos, budget, nested, is_block_start })
							} else if is_html_block_start(line) {
								Ok(raw_html_onto(out, { md, pos, budget, uploads }))
							} else if MdTable.is_table_at(md, pos) {
								table_onto(out, { md, pos, budget, uploads, dialect })
							} else {
								paragraph_onto(out, { md, pos, spacing, wrap, budget, uploads, dialect })
							}
					}
			}
	}

## An ATX heading, its content's inlines rendered between its tags.
heading_onto : List(U8), { level : U64, content : List(U8), after : U64, budget : MdText.Budget, uploads : MdSafety.Uploads, dialect : Dialect } -> Try(MdText.Block, [Hostile])
heading_onto = |out, { level, content, after, budget, uploads, dialect }| {
	heading = MdInline.render_onto({
		out: out.concat(
			match dialect {
				Chat => MdHtml.heading_open(level)
				Document(_) => MdHtml.heading_open_with_id(level, [])
			},
		),
		text: content,
		refs: inline_refs(dialect),
		budget,
		uploads,
	})?
	Ok({ out: heading.out.concat(MdHtml.heading_close(level)), budget: heading.budget, after })
}

## A paragraph: the longest run of lines that are not blank and start no
## block that may interrupt one. In the hard-wrap dialect each line is
## rendered on its own and joined by `<br>`; in reflow the lines join with
## a space and render once.
##
## **A BACKSLASH AT A LINE'S END** (CommonMark's hard line break, `foo\`
## then `bar`): in the hard-wrap dialect every line already breaks, so the
## backslash asks for what is there and is dropped; in reflow it is the
## `<br>` CommonMark makes, and the lines on either side render apart (so
## emphasis does not span it). On a paragraph's last line it is text, as
## CommonMark has it; an escaped one (`\\`) is a backslash, no break.
paragraph_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	spacing : [Tight, Loose],
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : Dialect,
} -> Try(MdText.Block, [Hostile])
paragraph_onto = |
	out,
	{
		md,
		pos,
		spacing,
		wrap,
		budget,
		uploads,
		dialect,
	},
| {
	len = md.len()
	var $lines = []
	var $p = pos
	while $p < len {
		eol = MdText.line_end(md, $p)
		line = MdText.cut(md, { start: $p, end: eol })
		if MdText.is_blank(line) or MdFence.open_at(
			md,
			$p,
		).is_ok() or atx_heading(line).is_ok() or MdList.is_list_interrupting(
			md,
			$p,
		) or MdQuote.is_quote_line(line) or ($p > pos and MdTable.is_table_at(md, $p)) {
			break
		} else {
			{}
		}
		$lines = $lines.append(line)
		$p = MdText.next_line(md, eol)
	}
	last = $lines.len() - 1
	var $out = if (spacing == Tight) out else out.concat(MdHtml.p_open)
	var $budget = budget
	var $reflow = []
	var $k = 0
	for line in $lines {
		breaks = $k < last and ends_in_hard_break(line)
		text = MdText.trim_line(if (breaks) line.drop_last(1) else line)
		if wrap == Reflow {
			$reflow = (if ($reflow == []) $reflow else $reflow.append(' ')).concat(text)
			if breaks {
				broke = MdInline.render_onto({
					out: $out,
					text: $reflow,
					refs: inline_refs(dialect),
					budget: $budget,
					uploads,
				})?
				$out = broke.out.concat(MdHtml.br)
				$budget = broke.budget
				$reflow = []
			} else {
				{}
			}
		} else {
			wrapped = MdInline.render_onto({
				out: if ($k == 0) $out else $out.concat(MdHtml.br),
				text,
				refs: inline_refs(dialect),
				budget: $budget,
				uploads,
			})?
			$out = wrapped.out
			$budget = wrapped.budget
		}
		$k = $k + 1
	}
	if wrap == Reflow {
		joined = MdInline.render_onto({
			out: $out,
			text: $reflow,
			refs: inline_refs(dialect),
			budget: $budget,
			uploads,
		})?
		$out = joined.out
		$budget = joined.budget
	} else {
		{}
	}
	Ok({
		out: if (spacing == Tight) $out else $out.concat(MdHtml.p_close),
		budget: $budget,
		after: $p,
	})
}

## CommonMark's hard line break: the line, as written, ends in an odd run of
## backslashes (an even one is escaped backslashes).
ends_in_hard_break : List(U8) -> Bool
ends_in_hard_break = |line| Bytes.count_back(line, |c| c == '\\') % 2 == 1

## How the inline pass reads a dialect's text.
inline_refs : Dialect -> [Linked, InLabel, Document]
inline_refs = |dialect| match dialect {
	Chat => Linked
	Document(_) => Document
}

## Inside a tight list item, a block after a bare
## paragraph starts on a line of its own.
tight_sep : List(U8), [Tight, Loose] -> List(U8)
tight_sep = |
	out,
	spacing,
| if (spacing == Tight and out != [] and out.last() != Ok('\n')) out.append('\n') else out

# ── fenced code ──

## The code block, up to its closing fence or the
## end (an unclosed fence runs to the end). Its body is charged whole, its
## close-scan and escape being linear in it; no check follows here.
fence_onto : List(U8),
{
	md : List(U8),
	open : { open : MdFence.Open, body_start : U64 },
	line : List(U8),
	budget : MdText.Budget,
	dialect : Dialect,
} -> MdText.Block
fence_onto = |
	out,
	{
		md,
		open: { open, body_start },
		line,
		budget,
		dialect,
	},
| {
	len = md.len()
	var $content_end = len
	var $after = len
	var $p = body_start
	while $p < len {
		eol = MdText.line_end(md, $p)
		if MdFence.is_close(
			MdText.cut(md, { start: $p, end: eol }),
			{ char: open.char, count: open.count },
		) {
			$content_end = $p
			$after = MdText.next_line(md, eol)
			break
		} else {
			$p = MdText.next_line(md, eol)
		}
	}
	content = MdText.cut(md, { start: body_start, end: $content_end })
	body = dedented({ content, indent: open.indent })
	code = || MdText.escape_onto(MdHtml.code_block_open(open.lang), body).concat(MdHtml.code_block_close)
	block = match dialect {
		Chat if MdChat.is_quote_fence(open.lang) => MdText.escape_onto(MdHtml.chat_quote_open, body).concat(MdHtml.chat_quote_close)
		Chat => code()
		Document(hook) =>
			match hook({ tag: open.lang, args: MdFence.args(line, open), body }) {
				Html(html) => html
				Pass => code()
			}
	}
	{
		out: out.concat(block),
		budget: MdText.charge(budget, content.len()),
		after: $after,
	}
}

## Each line ended with a newline, less up to the fence's own indent of
## spaces.
dedented : { content : List(U8), indent : U64 } -> List(U8)
dedented = |{ content, indent }| {
	len = content.len()
	var $out = []
	var $i = 0
	while $i < len {
		eol = MdText.line_end(content, $i)
		line = MdText.cut(content, { start: $i, end: eol })
		strip = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(indent)
		$out = $out.concat(line.drop_first(strip)).append('\n')
		$i = MdText.next_line(content, eol)
	}
	$out
}

# ── headings ──

## 1 to 6 `#` after up to three spaces, then a space,
## a tab or the line's end; a closing run of `#` is no content.
atx_heading : List(U8) -> Try({ level : U64, content : List(U8) }, [NotAHeading])
atx_heading = |line| {
	indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
	level_end = Bytes.count_while(line, { keep: |c| c == '#', at: indent })
	level = level_end - indent
	# The marks end the line, or a space or a tab follows them.
	is_ended = match line.get(level_end) {
		Ok(c) => c == ' ' or c == '\t'
		Err(OutOfBounds) => Bool.True
	}
	if indent >= 4 or level == 0 or level > 6 or !is_ended {
		Err(NotAHeading)
	} else {
		content = Bytes.trim(line.drop_first(level_end), heading_space)
		h = content.len() - Bytes.count_back(content, |c| c == '#')
		closed =
			if h < content.len() and (h == 0 or content.get(h - 1) == Ok(' ') or content.get(h - 1) == Ok('\t')) {
				Bytes.trim(content.take_first(h), heading_space)
			} else {
				content
			}
		Ok({ level, content: closed })
	}
}

# ── block starts ──

## The line at `pos` starts a block a lazy
## continuation may not take in (a blank line, a list item, a quote, a
## fence, a heading).
is_block_start : List(U8), U64 -> Bool
is_block_start = |md, pos| {
	line = MdText.cut(md, { start: pos, end: MdText.line_end(md, pos) })
	MdText.is_blank(line) or MdList.list_marker_at(
		md,
		pos,
	).is_ok() or MdQuote.is_quote_line(line) or MdFence.open_at(md, pos).is_ok() or atx_heading(line).is_ok()
}

# ── tables ──

## GFM's table from `pos` (MdTable `table_at`): its header row in `<thead>`, then a body row a
## line, up to a blank line or one that starts a block (is_block_start),
## each cut or padded to the header's width with empty cells. No body, no
## `<tbody>`. A unit a row and a unit a cell, checked a cell: a short row's
## padding is output its source never paid for.
table_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : Dialect,
} -> Try(MdText.Block, [Hostile])
table_onto = |out, { md, pos, budget, uploads, dialect }| match MdTable.table_at(md, pos) {
	Err(NotATable) => crash "Md.table_onto: no table where the dispatcher found one"
	Ok(table) => {
		len = md.len()
		head = row_onto(
			out.concat(MdHtml.table_open),
			{ cells: table.header, aligns: table.aligns, tag: Th, budget, uploads, dialect },
		)?
		var $out = head.out.concat(MdHtml.thead_close)
		var $budget = head.budget
		var $rows = 0
		var $p = table.body
		while $p < len and !is_block_start(md, $p) {
			eol = MdText.line_end(md, $p)
			row = row_onto(
				if ($rows == 0) $out.concat(MdHtml.tbody_open) else $out,
				{
					cells: MdTable.cells(MdText.cut(md, { start: $p, end: eol })),
					aligns: table.aligns,
					tag: Td,
					budget: $budget,
					uploads,
					dialect,
				},
			)?
			$out = row.out
			$budget = row.budget
			$rows = $rows + 1
			$p = MdText.next_line(md, eol)
		}
		Ok({
			out: (if ($rows == 0) $out else $out.concat(MdHtml.tbody_close)).concat(MdHtml.table_close),
			budget: $budget,
			after: $p,
		})
	}
}

## One `<tr>`: a cell a column, the row's own or an empty one, past the
## columns' count none.
row_onto : List(U8),
{
	cells : List(List(U8)),
	aligns : List(MdTable.Align),
	tag : [Th, Td],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : Dialect,
} -> Try(MdText.Rendered, [Hostile])
row_onto = |out, { cells, aligns, tag, budget, uploads, dialect }| {
	var $out = out.concat(MdHtml.tr_open)
	var $budget = MdText.charge(budget, 1)
	var $k = 0
	for align in aligns {
		$budget = MdText.charge($budget, 1)
		if MdText.is_blown($budget) {
			return Err(Hostile)
		} else {
			{}
		}
		cell = MdInline.render_onto({
			out: $out.concat(MdHtml.cell_open(tag, align)),
			text: cells.get($k) ?? [],
			refs: inline_refs(dialect),
			budget: $budget,
			uploads,
		})?
		$out = cell.out.concat(MdHtml.cell_close(tag))
		$budget = cell.budget
		$k = $k + 1
	}
	Ok({ out: $out.concat(MdHtml.tr_close), budget: $budget })
}

# ── raw HTML ──

## A raw block, every same-origin `<img>` and
## `<video>` rebuilt (MdMedia), every other byte escaped. One unit a byte.
raw_html_onto : List(U8), { md : List(U8), pos : U64, budget : MdText.Budget, uploads : MdSafety.Uploads } -> MdText.Block
raw_html_onto = |out, { md, pos, budget, uploads }| {
	# CommonMark's type 7: only at a block's start, and up to a blank line,
	# with no <p> and no newline added.
	md_len = md.len()
	var $p = MdText.next_line(md, MdText.line_end(md, pos))
	while $p < md_len and !MdText.is_blank(MdText.cut(md, { start: $p, end: MdText.line_end(md, $p) })) {
		$p = MdText.next_line(md, MdText.line_end(md, $p))
	}
	raw = MdText.cut(md, { start: pos, end: $p })
	len = raw.len()
	var $out = out
	var $last = 0
	var $i = 0
	while $i < len {
		if MdText.at(raw, $i) != '<' {
			$i = $i + 1
		} else {
			safe = match MdMedia.img_at(raw, $i, uploads) {
				Ok(tag) => Ok(tag)
				Err(NotSafe) => MdMedia.video_at(raw, $i, uploads)
			}
			match safe {
				Ok(tag) => {
					$out = MdText.escape_onto($out, MdText.cut(raw, { start: $last, end: $i })).concat(tag.html)
					$i = tag.end
					$last = tag.end
				}
				Err(NotSafe) => {
					$i = $i + 1
				}
			}
		}
	}
	{
		out: MdText.escape_onto($out, raw.drop_first($last)),
		budget: MdText.charge(budget, len),
		after: $p,
	}
}

## A whole open or close tag, then only
## whitespace (CommonMark's type 7).
is_html_block_start : List(U8) -> Bool
is_html_block_start = |line| {
	t = MdText.trim_line(line)
	match t {
		['<', second, ..] if Ascii.is_letter(second) or second == '/' =>
			match html_tag_end(t) {
				Ok(end) => MdText.is_blank(t.drop_first(end))
				Err(Unterminated) => Bool.False
			}
		_ => Bool.False
	}
}

## The index past the `>` closing the tag at `t[0]`,
## quoted values respected.
html_tag_end : List(U8) -> Try(U64, [Unterminated])
html_tag_end = |t| {
	len = t.len()
	var $i = 1
	while $i < len {
		c = MdText.at(t, $i)
		if c == '"' or c == '\'' {
			close = MdText.find_or_end(t, { byte: c, at: $i + 1 })
			if close >= len {
				return Err(Unterminated)
			} else {
				$i = close + 1
			}
		} else if c == '>' {
			return Ok($i + 1)
		} else {
			$i = $i + 1
		}
	}
	Err(Unterminated)
}

heading_space : List(U8)
heading_space = [' ', '\t']

# The chat's own options, as roc-chat passes them.
chat : Md.Options
chat = { uploads: Md.uploads_under("/user_uploads/".to_utf8()) }

md : Str -> Str

md = |text| Str.from_utf8(Md.render(text.to_utf8(), chat)) ?? "not text"

# Whole messages, block by block: the media rule, hard wraps and their
# backslash, fences, lists, quotes and headings as the dialect renders them.
expect md("<video src=\"/user_uploads/1_3/abc.mp4\"></video>") == "<p><video controls preload=\"metadata\" src=\"/user_uploads/1_3/abc.mp4\"></video></p>\n"
# Media outside the host's uploads is text: under roc-chat's rule, the old
# chat's upload paths too.
expect md("<video src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video>") == "<p>&lt;video src=&quot;/chat/c/1_3/yo/uploads/abc.mp4&quot;&gt;&lt;/video&gt;</p>\n"
expect md("hello\nworld") == "<p>hello<br>\nworld</p>\n"
expect Md.escape("Bea <i>x</i> & \"co\" 'q'".to_utf8()) == "Bea &lt;i&gt;x&lt;/i&gt; &amp; &quot;co&quot; &#39;q&#39;".to_utf8()
expect md("hello\\\nworld") == "<p>hello<br>\nworld</p>\n"
expect md("hello\\\\\nworld") == "<p>hello\\<br>\nworld</p>\n"
expect md("hello\\") == "<p>hello\\</p>\n"
expect Str.from_utf8(Md.render_trusted_reflow("*a\\\nb* c\nd".to_utf8(), chat)) == Ok("<p>*a<br>\nb* c d</p>\n")
expect md("# about MSG_plans_3") == "<h1>about <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></h1>\n"
expect md("```zig\na<b\n```\nafter") == "<pre><code class=\"language-zig\">a&lt;b\n</code></pre>\n<p>after</p>\n"
expect md("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
# A blank line inside an item stays: two paragraphs, a fence's blank line.
expect md("- one\n\n  two") == "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n"
expect md("- ```\n  a\n\n  b") == "<ul>\n<li>\n<pre><code>a\n\nb\n</code></pre>\n</li>\n</ul>\n"
expect md("> q\nlazy") == "<blockquote>\n<p>q<br>\nlazy</p>\n</blockquote>\n"
expect Str.from_utf8(Md.render_trusted_reflow("A **bold phrase that\nspans two lines** here.".to_utf8(), chat)) == Ok("<p>A <strong>bold phrase that spans two lines</strong> here.</p>\n")
expect Md.hostility("some **bold** text and a [link](http://x.com)".to_utf8(), chat) == Renderable
# GFM's tables.
expect md("| a | b |\n| :- | -: |\n| c |\n| d | e | f |") == "<table>\n<thead>\n<tr>\n<th align=\"left\">a</th>\n<th align=\"right\">b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">c</td>\n<td align=\"right\"></td>\n</tr>\n<tr>\n<td align=\"left\">d</td>\n<td align=\"right\">e</td>\n</tr>\n</tbody>\n</table>\n"
expect md("see:\n| a |\n| - |\n\nafter") == "<p>see:</p>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>\n<p>after</p>\n"
expect md("| a | b |\n| - |") == "<p>| a | b |<br>\n| - |</p>\n"
# A pipe in a code span splits its cell all the same: GFM splits first.
expect md("| a | b |\n| - | - |\n| `x|y` |") == "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>`x</td>\n<td>y`</td>\n</tr>\n</tbody>\n</table>\n"
# A tight item whose first child is a table starts it on a line of its own.
expect md("- | a |\n  | - |\n  | b |\n- next") == "<ul>\n<li>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n</li>\n<li>next</li>\n</ul>\n"
# No line is lazy after a quoted table: its rows are no paragraph.
expect md("> | a |\n> | - |\n> | MSG_x_1 |\nlazy") == "<blockquote>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><a href=\"#msg-x_1\" class=\"msg-ref\">MSG_x_1</a></td>\n</tr>\n</tbody>\n</table>\n</blockquote>\n<p>lazy</p>\n"

# A document's render, and a chat's of the same text beside it.
widgets : MdDocument.FenceHook
widgets = |{ tag, args, body }|
	if tag == "widget".to_utf8() {
		Html("<iframe src=\"/w/".to_utf8().concat(args).concat("\"></iframe>\n".to_utf8()))
	} else if tag == "dot".to_utf8() {
		Html("<svg>".to_utf8().concat(body).concat("</svg>\n".to_utf8()))
	} else if tag == "heading".to_utf8() {
		Html("<h2>mine</h2>\n<h2 id=\"x\">too</h2>\n".to_utf8())
	} else {
		Pass
	}

doc : Str -> Str
doc = |text| Str.from_utf8(Md.render_document(text.to_utf8(), { fence: widgets }).html) ?? "not text"

# The hook answers with HTML, unescaped, or passes the fence on as code.
expect doc("```widget sky\n```\n") == "<iframe src=\"/w/sky\"></iframe>\n"
expect doc("```dot\na -> b\n```") == "<svg>a -> b\n</svg>\n"
expect doc("```roc\na<b\n```") == "<pre><code class=\"language-roc\">a&lt;b\n</code></pre>\n"
expect doc("```\na\n```") == "<pre><code>a\n</code></pre>\n"
expect doc("  ```dot\n  a\n   b\n  ```") == "<svg>a\n b\n</svg>\n"
expect doc("- x\n\n  ```dot\n  a\n  ```\n") == "<ul>\n<li>\n<p>x</p>\n<svg>a\n</svg>\n</li>\n</ul>\n"
# A chat has no hook, so the same fences are code.
expect md("```widget sky\n```\n") == "<pre><code class=\"language-widget\"></code></pre>\n"
expect md("```dot\na -> b\n```") == "<pre><code class=\"language-dot\">a -&gt; b\n</code></pre>\n"

# The chat's syntax is off in a document, and on in a chat.
expect doc("see MSG_plans_3") == "<p>see MSG_plans_3</p>\n"
expect md("see MSG_plans_3") == "<p>see <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></p>\n"
expect doc("```quote\nhi\n```") == "<pre><code class=\"language-quote\">hi\n</code></pre>\n"
expect md("```quote\nhi\n```") == "<pre class=\"chat-quote\">hi\n</pre>\n"

# A link to another site stays in its tab in a document, in every form.
expect doc("[a](https://x.org) https://y.org www.z.org") == "<p><a href=\"https://x.org\">a</a> <a href=\"https://y.org\">https://y.org</a> <a href=\"http://www.z.org\">www.z.org</a></p>\n"
expect md("[a](https://x.org) https://y.org www.z.org") == "<p><a href=\"https://x.org\" target=\"_blank\" rel=\"noopener\">a</a> <a href=\"https://y.org\" target=\"_blank\" rel=\"noopener\">https://y.org</a> <a href=\"http://www.z.org\" target=\"_blank\" rel=\"noopener\">www.z.org</a></p>\n"
expect doc("[a MSG_x_1](https://y.org)") == "<p><a href=\"https://y.org\">a MSG_x_1</a></p>\n"
expect doc("![b](https://x.org/i.png)") == "<p><a href=\"https://x.org/i.png\">b</a></p>\n"
expect md("![b](https://x.org/i.png)") == "<p><a href=\"https://x.org/i.png\" target=\"_blank\" rel=\"noopener\">b</a></p>\n"
expect doc("[js](javascript:alert(1))") == "<p>[js](javascript:alert(1))</p>\n"

# Tables and nested lists are the chat's, in a document too.
expect doc("| a | b |\n| - | :-: |\n| c | `d` |\n") == md("| a | b |\n| - | :-: |\n| c | `d` |\n")
expect doc("- a\n  - b\n\n    ```roc\n    c\n    ```\n- d\n") == md("- a\n  - b\n\n    ```roc\n    c\n    ```\n- d\n")

# A newline is a space, and raw HTML is escaped, media and all.
expect doc("a\nb") == "<p>a b</p>\n"
expect md("a\nb") == "<p>a<br>\nb</p>\n"
expect doc("<div>x</div>") == "<p>&lt;div&gt;x&lt;/div&gt;</p>\n"
expect doc("<video src=\"/user_uploads/a.mp4\"></video>") == "<p>&lt;video src=&quot;/user_uploads/a.mp4&quot;&gt;&lt;/video&gt;</p>\n"
expect doc("<img src=\"/user_uploads/a.png\">") == "&lt;img src=&quot;/user_uploads/a.png&quot;&gt;"
expect md("<img src=\"/user_uploads/a.png\">") == "<img src=\"/user_uploads/a.png\">"

# A document's headings have ids, wherever they stand; a chat's have none.
expect doc("## The *sky*") == "<h2 id=\"the-sky\">The <em>sky</em></h2>\n"
expect md("## The *sky*") == "<h2>The <em>sky</em></h2>\n"
expect Md.render_document("# A\n\n> ## A\n\n- ## `A`\n".to_utf8(), { fence: widgets }).headings == [
	{ level: 1, id: "a".to_utf8(), text: "A".to_utf8() },
	{ level: 2, id: "a-2".to_utf8(), text: "A".to_utf8() },
	{ level: 2, id: "a-3".to_utf8(), text: "A".to_utf8() },
]
# A heading in a code block is code, and a hook's own stay as the hook wrote them.
expect Md.render_document("```\n## no\n```".to_utf8(), { fence: widgets }).headings == []
expect Md.render_document("<h2 id=\"\">x</h2>\n\na <h2 id=\"\">b</h2>".to_utf8(), { fence: widgets }).headings == []
expect doc("```heading\n```\n# mine") == "<h2>mine</h2>\n<h2 id=\"x\">too</h2>\n<h1 id=\"mine\">mine</h1>\n"

# The chat's answers for a text with every feature here, in each mode a
# chat has.
every_feature : Str
every_feature = "# a MSG_x_1\n\nb\nc [d](https://x.org) https://y.org\n\n```quote\ne\n```\n\n```dot\nf\n```\n\n| g |\n| - |\n| h |\n\n<video src=\"/user_uploads/i.mp4\"></video>\n"

every_feature_html : Str -> Str
every_feature_html = |line_join| "<h1>a <a href=\"#msg-x_1\" class=\"msg-ref\">MSG_x_1</a></h1>\n<p>b${line_join}c <a href=\"https://x.org\" target=\"_blank\" rel=\"noopener\">d</a> <a href=\"https://y.org\" target=\"_blank\" rel=\"noopener\">https://y.org</a></p>\n<pre class=\"chat-quote\">e\n</pre>\n<pre><code class=\"language-dot\">f\n</code></pre>\n<table>\n<thead>\n<tr>\n<th>g</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>h</td>\n</tr>\n</tbody>\n</table>\n<p><video controls preload=\"metadata\" src=\"/user_uploads/i.mp4\"></video></p>\n"

expect md(every_feature) == every_feature_html("<br>\n")
expect Str.from_utf8(Md.render_trusted(every_feature.to_utf8(), chat)) == Ok(every_feature_html("<br>\n"))
expect Str.from_utf8(Md.render_trusted_reflow(every_feature.to_utf8(), chat)) == Ok(every_feature_html(" "))
expect Md.hostility(every_feature.to_utf8(), chat) == Renderable
