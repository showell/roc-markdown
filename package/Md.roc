## **THE CHAT'S MARKDOWN** (ported from chat-markdown markdown.zig, metal-vmm
## QUEUE 305; this is the dialect's definition now): a member's message to
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
## starts it asks about (`is_block_start`, `is_table_at`), rather than each
## importing Md, a cycle. A new block kind is a branch of `blocks_onto`, and
## a line of `is_block_start` (and of `paragraph_onto`'s stop) when it
## interrupts a paragraph.
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
import MdFence
import MdHtml
import MdInline
import MdList
import MdMedia
import MdQuote
import MdTable

Md := [].{

	## markdown `render`: a member's message, with its budget; a hostile one
	## is `malformed_html`.
	render : List(U8) -> List(U8)
	render = |md| rendered(md, { wrap: HardWrap, budget: MdText.for_input(md) })

	## markdown `renderTrusted`: server-owned text, never a request's, with no
	## limit on its work. The depth cap and the escaping still hold.
	render_trusted : List(U8) -> List(U8)
	render_trusted = |md| rendered(md, { wrap: HardWrap, budget: MdText.unlimited })

	## markdown `renderTrustedReflow`: server-owned prose, whose source line
	## wraps join with a space rather than a `<br>`, so a span may cross one
	## and the text rewraps to the reader's width.
	render_trusted_reflow : List(U8) -> List(U8)
	render_trusted_reflow = |md| rendered(md, { wrap: Reflow, budget: MdText.unlimited })

	## markdown `workUnits`: the work a render of `md` costs, unlimited, the
	## measure the budget caps.
	work_units : List(U8) -> U64
	work_units = |md| match blocks_onto({
		out: [],
		md,
		spacing: Loose,
		depth: 0,
		wrap: HardWrap,
		budget: MdText.unlimited,
	}) {
		Ok(done) => done.budget.spent
		Err(Hostile) => crash "Md.work_units: an unlimited budget blown"
	}

	## markdown `hostileReason`: whether `md` would blow its budget, so a POST
	## refuses it. One render in good faith with the real budget.
	hostility : List(U8) -> [Renderable, TooMuchFormatting]
	hostility = |md| match blocks_onto({
		out: [],
		md,
		spacing: Loose,
		depth: 0,
		wrap: HardWrap,
		budget: MdText.for_input(md),
	}) {
		Ok(_) => Renderable
		Err(Hostile) => TooMuchFormatting
	}

	## The words a refused POST says, the Zig's.
	too_much_formatting : Str
	too_much_formatting = "too much markdown formatting"

	## What a hostile message renders as: an escaped paragraph, the client
	## free to style `.md-malformed`.
	malformed_html : List(U8)
	malformed_html = MdHtml.malformed
}

rendered : List(U8), { wrap : [HardWrap, Reflow], budget : MdText.Budget } -> List(U8)
rendered = |md, { wrap, budget }| match blocks_onto({
	out: [],
	md,
	spacing: Loose,
	depth: 0,
	wrap,
	budget,
}) {
	Ok(done) => done.out
	Err(Hostile) => Md.malformed_html
}

## markdown `max_block_depth`: quotes and lists nest at most this deep;
## past it, the rest renders as one paragraph. Ordinary conversation never
## nests past about 10 (Steve, 2026-06-19).
max_block_depth : U64
max_block_depth = 16

## markdown `renderBlocksInto`, the block dispatcher: `md`'s blocks onto
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
} -> Try(MdText.Rendered, [Hostile])
blocks_onto = |
	{
		out,
		md,
		spacing,
		depth,
		wrap,
		budget,
	},
|
	if depth > max_block_depth {
		start = if out != [] and List.last(out) != Ok('\n') List.append(out, '\n') else out
		flat = MdInline.render_onto({
			out: List.concat(start, MdHtml.p_open),
			text: md,
			refs: Linked,
			budget,
		})?
		Ok({ out: List.concat(flat.out, MdHtml.p_close), budget: flat.budget })
	} else {
		len = List.len(md)
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
				# A fence, a heading, a list and a quote can each interrupt a
				# paragraph, so each is asked first.
				match fence_open_at(md, $pos) {
					Ok(open) => {
						fenced = fence_onto(
							tight_sep($out, spacing),
							{
								md,
								open,
								budget: $budget,
							},
						)
						$out = fenced.out
						$budget = fenced.budget
						$pos = fenced.after
					}
					Err(NotAFence) =>
						match atx_heading(line) {
							Ok(h) => {
								heading = MdInline.render_onto({
									out: List.concat(tight_sep($out, spacing), MdHtml.heading_open(h.level)),
									text: h.content,
									refs: Linked,
									budget: $budget,
								})?
								$out = List.concat(heading.out, MdHtml.heading_close(h.level))
								$budget = heading.budget
								$pos = next
							}
							Err(NotAHeading) =>
								match MdList.list_marker_at(md, $pos) {
									Ok(marker) => {
										listed = MdList.list_onto(
											tight_sep($out, spacing),
											{
												md,
												pos: $pos,
												first: marker,
												budget: $budget,
												nested,
												is_block_start,
												is_table_at,
											},
										)?
										$out = listed.out
										$budget = listed.budget
										$pos = listed.after
									}
									Err(NotAMarker) =>
										if MdQuote.is_quote_line(line) {
											quoted = MdQuote.quote_onto(
												tight_sep($out, spacing),
												{
													md,
													pos: $pos,
													budget: $budget,
													nested,
													is_block_start,
													is_table_at,
												},
											)?
											$out = quoted.out
											$budget = quoted.budget
											$pos = quoted.after
										} else if is_html_block_start(line) {
											# CommonMark's type 7: only at a block's start, and
											# up to a blank line, its source passed through the
											# escape but for a same-origin <img> or <video>, with
											# no <p> and no newline added.
											var $p = next
											while $p < len and !MdText.is_blank(
												MdText.cut(
													md,
													{ start: $p, end: MdText.line_end(md, $p) },
												),
											) {
												$p = MdText.next_line(md, MdText.line_end(md, $p))
											}
											raw = raw_html_onto(
												tight_sep($out, spacing),
												{
													raw: MdText.cut(md, { start: $pos, end: $p }),
													budget: $budget,
												},
											)
											$out = raw.out
											$budget = raw.budget
											$pos = $p
										} else if is_table_at(md, $pos) {
											tabled = table_onto(
												tight_sep($out, spacing),
												{ md, pos: $pos, budget: $budget },
											)?
											$out = tabled.out
											$budget = tabled.budget
											$pos = tabled.after
										} else {
											para = paragraph_onto(
												tight_sep($out, spacing),
												{
													md,
													pos: $pos,
													spacing,
													wrap,
													budget: $budget,
												},
											)?
											$out = para.out
											$budget = para.budget
											$pos = para.after
										}
								}
						}
				}
			}
		}
		Ok({ out: $out, budget: $budget })
	}

## A paragraph: the longest run of lines that are not blank and start no
## block that may interrupt one. In the hard-wrap dialect each line is
## rendered on its own and joined by `<br>`; in reflow the lines join with
## a space and render once.
paragraph_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	spacing : [Tight, Loose],
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
} -> Try(MdText.Block, [Hostile])
paragraph_onto = |
	out,
	{
		md,
		pos,
		spacing,
		wrap,
		budget,
	},
| {
	len = List.len(md)
	var $out = if spacing == Tight out else List.concat(out, MdHtml.p_open)
	var $budget = budget
	var $reflow = []
	var $first = Bool.True
	var $p = pos
	while $p < len {
		eol = MdText.line_end(md, $p)
		line = MdText.cut(md, { start: $p, end: eol })
		if MdText.is_blank(line) or fence_open_at(
			md,
			$p,
		).is_ok() or atx_heading(line).is_ok() or MdList.is_list_interrupting(
			md,
			$p,
		) or MdQuote.is_quote_line(line) or ($p > pos and is_table_at(md, $p)) {
			break
		} else {
			{}
		}
		if wrap == Reflow {
			$reflow = List.concat(
				if $first $reflow else List.append($reflow, ' '),
				MdText.trim_line(line),
			)
		} else {
			wrapped = MdInline.render_onto({
				out: if $first $out else List.concat($out, MdHtml.br),
				text: MdText.trim_line(line),
				refs: Linked,
				budget: $budget,
			})?
			$out = wrapped.out
			$budget = wrapped.budget
		}
		$first = Bool.False
		$p = MdText.next_line(md, eol)
	}
	if wrap == Reflow {
		joined = MdInline.render_onto({
			out: $out,
			text: $reflow,
			refs: Linked,
			budget: $budget,
		})?
		$out = joined.out
		$budget = joined.budget
	} else {
		{}
	}
	Ok({
		out: if spacing == Tight $out else List.concat($out, MdHtml.p_close),
		budget: $budget,
		after: $p,
	})
}

## markdown `tightSep`: inside a tight list item, a block after a bare
## paragraph starts on a line of its own.
tight_sep : List(U8), [Tight, Loose] -> List(U8)
tight_sep = |
	out,
	spacing,
| if spacing == Tight and out != [] and List.last(out) != Ok('\n') List.append(out, '\n') else out

# ── fenced code ──

## A fence's opening at the line at `pos`, and where its body starts.
fence_open_at : List(U8), U64 -> Try({ open : MdFence.Open, body_start : U64 }, [NotAFence])
fence_open_at = |md, pos| {
	eol = MdText.line_end(md, pos)
	open = MdFence.open(MdText.cut(md, { start: pos, end: eol }))?
	Ok({ open, body_start: MdText.next_line(md, eol) })
}

## markdown `renderFence`: the code block, up to its closing fence or the
## end (an unclosed fence runs to the end). Its body is charged whole, its
## close-scan and escape being linear in it; no check follows here.
fence_onto : List(U8),
{
	md : List(U8),
	open : { open : MdFence.Open, body_start : U64 },
	budget : MdText.Budget,
} -> MdText.Block
fence_onto = |
	out,
	{
		md,
		open: { open, body_start },
		budget,
	},
| {
	len = List.len(md)
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
	is_quote = MdChat.is_quote_fence(open.lang)
	(head, tail) = if is_quote (MdHtml.chat_quote_open, MdHtml.chat_quote_close) else (MdHtml.code_block_open(open.lang), MdHtml.code_block_close)
	code = code_lines_onto(List.concat(out, head), { content, indent: open.indent })
	{
		out: List.concat(code, tail),
		budget: MdText.charge(budget, List.len(content)),
		after: $after,
	}
}

## markdown `writeCodeLines`: each line escaped and ended with a newline,
## less up to the fence's own indent of spaces.
code_lines_onto : List(U8), { content : List(U8), indent : U64 } -> List(U8)
code_lines_onto = |out, { content, indent }| {
	len = List.len(content)
	var $out = out
	var $i = 0
	while $i < len {
		eol = MdText.line_end(content, $i)
		line = MdText.cut(content, { start: $i, end: eol })
		strip = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), indent)
		$out = List.append(MdText.escape_onto($out, List.drop_first(line, strip)), '\n')
		$i = MdText.next_line(content, eol)
	}
	$out
}

# ── headings ──

## markdown `atxHeading`: 1 to 6 `#` after up to three spaces, then a space,
## a tab or the line's end; a closing run of `#` is no content.
atx_heading : List(U8) -> Try({ level : U64, content : List(U8) }, [NotAHeading])
atx_heading = |line| {
	indent = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), 4)
	level_end = Bytes.count_while(line, { keep: |c| c == '#', at: indent })
	level = level_end - indent
	# The marks end the line, or a space or a tab follows them.
	is_ended = match List.get(line, level_end) {
		Ok(c) => c == ' ' or c == '\t'
		Err(OutOfBounds) => Bool.True
	}
	if indent >= 4 or level == 0 or level > 6 or !is_ended {
		Err(NotAHeading)
	} else {
		content = Bytes.trim(List.drop_first(line, level_end), heading_space)
		h = List.len(content) - Bytes.count_back(content, |c| c == '#')
		closed =
			if h < List.len(content) and (
				h == 0 or List.get(
					content,
					h - 1,
				) == Ok(' ') or List.get(content, h - 1) == Ok('\t')
			) {
				Bytes.trim(List.take_first(content, h), heading_space)
			} else {
				content
			}
		Ok({ level, content: closed })
	}
}

# ── block starts ──

## markdown `lineStartsBlock`: the line at `pos` starts a block a lazy
## continuation may not take in (a blank line, a list item, a quote, a
## fence, a heading).
is_block_start : List(U8), U64 -> Bool
is_block_start = |md, pos| {
	line = MdText.cut(md, { start: pos, end: MdText.line_end(md, pos) })
	MdText.is_blank(line) or MdList.list_marker_at(
		md,
		pos,
	).is_ok() or MdQuote.is_quote_line(line) or fence_open_at(md, pos).is_ok() or atx_heading(line).is_ok()
}

# ── tables ──

## GFM's table at the line at `pos`: that line is its header row and the
## next a delimiter row (MdTable) of as many cells. Its header's cells, each
## column's alignment, and where its body starts.
Table : {
	header : List(List(U8)),
	aligns : List(MdTable.Align),
	body : U64,
}

table_at : List(U8), U64 -> Try(Table, [NotATable])
table_at = |md, pos| {
	eol = MdText.line_end(md, pos)
	if eol >= List.len(md) {
		Err(NotATable)
	} else {
		delim_end = MdText.line_end(md, eol + 1)
		match MdTable.delimiter_row(MdText.cut(md, { start: eol + 1, end: delim_end })) {
			Err(NotADelimiter) => Err(NotATable)
			Ok(aligns) => {
				header = MdTable.cells(MdText.cut(md, { start: pos, end: eol }))
				if List.len(header) == List.len(aligns) {
					Ok({ header, aligns, body: MdText.next_line(md, delim_end) })
				} else {
					Err(NotATable)
				}
			}
		}
	}
}

is_table_at : List(U8), U64 -> Bool
is_table_at = |md, pos| table_at(md, pos).is_ok()

## GFM's table from `pos`: its header row in `<thead>`, then a body row a
## line, up to a blank line or one that starts a block (is_block_start),
## each cut or padded to the header's width with empty cells. No body, no
## `<tbody>`. A unit a row and a unit a cell, checked a cell: a short row's
## padding is output its source never paid for.
table_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	budget : MdText.Budget,
} -> Try(MdText.Block, [Hostile])
table_onto = |out, { md, pos, budget }| match table_at(md, pos) {
	Err(NotATable) => crash "Md.table_onto: no table where the dispatcher found one"
	Ok(table) => {
		len = List.len(md)
		head = row_onto(
			List.concat(out, MdHtml.table_open),
			{ cells: table.header, aligns: table.aligns, tag: Th, budget },
		)?
		var $out = List.concat(head.out, MdHtml.thead_close)
		var $budget = head.budget
		var $rows = 0
		var $p = table.body
		while $p < len and !is_block_start(md, $p) {
			eol = MdText.line_end(md, $p)
			row = row_onto(
				if $rows == 0 List.concat($out, MdHtml.tbody_open) else $out,
				{
					cells: MdTable.cells(MdText.cut(md, { start: $p, end: eol })),
					aligns: table.aligns,
					tag: Td,
					budget: $budget,
				},
			)?
			$out = row.out
			$budget = row.budget
			$rows = $rows + 1
			$p = MdText.next_line(md, eol)
		}
		Ok({
			out: List.concat(if $rows == 0 $out else List.concat($out, MdHtml.tbody_close), MdHtml.table_close),
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
} -> Try(MdText.Rendered, [Hostile])
row_onto = |out, { cells, aligns, tag, budget }| {
	var $out = List.concat(out, MdHtml.tr_open)
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
			out: List.concat($out, MdHtml.cell_open(tag, align)),
			text: List.get(cells, $k) ?? [],
			refs: Linked,
			budget: $budget,
		})?
		$out = List.concat(cell.out, MdHtml.cell_close(tag))
		$budget = cell.budget
		$k = $k + 1
	}
	Ok({ out: List.concat($out, MdHtml.tr_close), budget: $budget })
}

# ── raw HTML ──

## markdown `writeRawHtml`: a raw block, every same-origin `<img>` and
## `<video>` rebuilt (MdMedia), every other byte escaped. One unit a byte.
raw_html_onto : List(U8), { raw : List(U8), budget : MdText.Budget } -> MdText.Rendered
raw_html_onto = |out, { raw, budget }| {
	len = List.len(raw)
	var $out = out
	var $last = 0
	var $i = 0
	while $i < len {
		if MdText.at(raw, $i) != '<' {
			$i = $i + 1
		} else {
			safe = match MdMedia.img_at(raw, $i) {
				Ok(tag) => Ok(tag)
				Err(NotSafe) => MdMedia.video_at(raw, $i)
			}
			match safe {
				Ok(tag) => {
					$out = List.concat(
						MdText.escape_onto($out, MdText.cut(raw, { start: $last, end: $i })),
						tag.html,
					)
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
		out: MdText.escape_onto($out, List.drop_first(raw, $last)),
		budget: MdText.charge(budget, len),
	}
}

## markdown `isHtmlBlockStart`: a whole open or close tag, then only
## whitespace (CommonMark's type 7).
is_html_block_start : List(U8) -> Bool
is_html_block_start = |line| {
	t = MdText.trim_line(line)
	match t {
		['<', second, ..] if Ascii.is_letter(second) or second == '/' =>
			match html_tag_end(t) {
				Ok(end) => MdText.is_blank(List.drop_first(t, end))
				Err(Unterminated) => Bool.False
			}
		_ => Bool.False
	}
}

## markdown `htmlTagEnd`: the index past the `>` closing the tag at `t[0]`,
## quoted values respected.
html_tag_end : List(U8) -> Try(U64, [Unterminated])
html_tag_end = |t| {
	len = List.len(t)
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

md : Str -> Str
md = |text| Str.from_utf8(Md.render(Str.to_utf8(text))) ?? "not text"

# markdown.zig's own cases.
expect md("<video src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video>") == "<p><video controls preload=\"metadata\" src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video></p>\n"
expect md("hello\nworld") == "<p>hello<br>\nworld</p>\n"
expect md("# about MSG_plans_3") == "<h1>about <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></h1>\n"
expect md("```zig\na<b\n```\nafter") == "<pre><code class=\"language-zig\">a&lt;b\n</code></pre>\n<p>after</p>\n"
expect md("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
# A blank line inside an item stays: two paragraphs, a fence's blank line.
expect md("- one\n\n  two") == "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n"
expect md("- ```\n  a\n\n  b") == "<ul>\n<li>\n<pre><code>a\n\nb\n</code></pre>\n</li>\n</ul>\n"
expect md("> q\nlazy") == "<blockquote>\n<p>q<br>\nlazy</p>\n</blockquote>\n"
expect Str.from_utf8(Md.render_trusted_reflow(Str.to_utf8("A **bold phrase that\nspans two lines** here."))) == Ok("<p>A <strong>bold phrase that spans two lines</strong> here.</p>\n")
expect Md.hostility(Str.to_utf8("some **bold** text and a [link](http://x.com)")) == Renderable
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
