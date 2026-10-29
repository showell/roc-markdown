## **THE CHAT'S MARKDOWN** (chat-markdown markdown.zig, the definition of
## the dialect, ported faithfully; metal-vmm QUEUE 305): a member's message
## to HTML. GFM-style paragraphs with hard wraps, ATX headings, fenced code
## (with the `quote` fence of a reply), lists, blockquotes, and the raw
## HTML block, which is escaped but for a same-origin `<img>` or `<video>`
## (MdMedia); each line's inline content is MdInline's. Pure.
##
## **THE PARSER IS THE JUDGE OF HOSTILITY**: a render charges its work to a
## budget (MdText), checked at each block line and each inline step, and a
## message that blows it renders as `malformed_html` and is refused at
## POST (`hostility`). There is no second model of "too much" to drift from
## the parser. The work, unit for unit, is the Zig's: angry-gopher's
## markdown_twin_test.zig holds every corpus case to equal html and equal
## `work_units`.
##
## A block nested past `max_block_depth` renders as one flat paragraph, so
## no message recurses deeper than that; every walk along a line is a loop.
import Ascii
import Bytes
import MdText
import MdFence
import MdInline
import MdMedia

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
	malformed_html = Str.to_utf8("<p class=\"md-malformed\">⚠️ malformed markdown — not rendered</p>\n")
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
			out: List.concat(start, p_open),
			text: md,
			refs: Linked,
			budget,
		})?
		Ok({ out: List.concat(flat.out, p_close), budget: flat.budget })
	} else {
		len = List.len(md)
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
								digit = '0' + h.level.to_u8_wrap()
								heading = MdInline.render_onto({
									out: List.concat(
										tight_sep($out, spacing),
										[
											'<',
											'h',
											digit,
											'>',
										],
									),
									text: h.content,
									refs: Linked,
									budget: $budget,
								})?
								$out = List.concat(
									heading.out,
									[
										'<',
										'/',
										'h',
										digit,
										'>',
										'\n',
									],
								)
								$budget = heading.budget
								$pos = next
							}
							Err(NotAHeading) =>
								match list_marker_at(md, $pos) {
									Ok(marker) => {
										listed = list_onto(
											tight_sep($out, spacing),
											{
												md,
												pos: $pos,
												first: marker,
												depth,
												wrap,
												budget: $budget,
											},
										)?
										$out = listed.out
										$budget = listed.budget
										$pos = listed.after
									}
									Err(NotAMarker) =>
										if is_quote_line(line) {
											quoted = quote_onto(
												tight_sep($out, spacing),
												{
													md,
													pos: $pos,
													depth,
													wrap,
													budget: $budget,
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

## What a block's renderer made, and where the source after it starts.
Block : {
	out : List(U8),
	budget : MdText.Budget,
	after : U64,
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
} -> Try(Block, [Hostile])
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
	var $out = if spacing == Tight out else List.concat(out, Str.to_utf8("<p>"))
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
		).is_ok() or atx_heading(line).is_ok() or is_list_interrupting(
			md,
			$p,
		) or is_quote_line(line) {
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
				out: if $first $out else List.concat($out, br),
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
		out: if spacing == Tight $out else List.concat($out, p_close),
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
} -> Block
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
	is_quote = open.lang == Str.to_utf8("quote")
	head =
		if is_quote {
			Str.to_utf8("<pre class=\"chat-quote\">")
		} else if open.lang == [] {
			Str.to_utf8("<pre><code>")
		} else {
			List.concat(
				MdText.escape_onto(Str.to_utf8("<pre><code class=\"language-"), open.lang),
				['"', '>'],
			)
		}
	code = code_lines_onto(List.concat(out, head), { content, indent: open.indent })
	{
		out: List.concat(code, Str.to_utf8(if is_quote "</pre>\n" else "</code></pre>\n")),
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

# ── lists ──

## A list item's marker: its kind, the spaces before it, the column its
## content starts at (the item's indent), and where its content starts in
## the source.
Marker : {
	kind : [Bullet(U8), Ordered({ start : U64, delim : U8 })],
	content_col : U64,
	content_start : U64,
}

## markdown `listMarkerAt`: up to three spaces, then `-`, `+`, `*`, or up to
## nine digits and `.` or `)`, then a space, a tab or the line's end. One
## to four spaces after are the content's indent; more is one, the rest the
## content's.
list_marker_at : List(U8), U64 -> Try(Marker, [NotAMarker])
list_marker_at = |md, pos| {
	eol = MdText.line_end(md, pos)
	line = MdText.cut(md, { start: pos, end: eol })
	n = List.len(line)
	indent = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), 4)
	if indent >= 4 or indent >= n {
		Err(NotAMarker)
	} else {
		c = MdText.at(line, indent)
		found =
			if c == '-' or c == '+' or c == '*' {
				Ok({ kind: Bullet(c), marker_end: indent + 1 })
			} else if Ascii.is_digit(c) {
				digits_end = U64.min(
					Bytes.count_while(line, { keep: Ascii.is_digit, at: indent }),
					indent + 9,
				)
				match List.get(line, digits_end) {
					Ok(delim) if delim == '.' or delim == ')' => {
						start = List.fold(
							MdText.cut(line, { start: indent, end: digits_end }),
							0,
							|acc, d| acc * 10 + (d - '0').to_u64(),
						)
						Ok({ kind: Ordered({ start, delim }), marker_end: digits_end + 1 })
					}
					_ => Err(NotAMarker)
				}
			} else {
				Err(NotAMarker)
			}
		{ kind, marker_end } = found?
		after = List.get(line, marker_end)
		if after != Err(OutOfBounds) and after != Ok(' ') and after != Ok('\t') {
			Err(NotAMarker)
		} else {
			spaces = Bytes.count_while(line, { keep: |s| s == ' ', at: marker_end }) - marker_end
			if marker_end >= n {
				Ok({
					kind,
					content_col: marker_end + 1,
					content_start: eol,
				})
			} else if spaces == 0 or spaces > 4 {
				Ok({
					kind,
					content_col: marker_end + 1,
					content_start: pos + marker_end + (if spaces == 0 0 else 1),
				})
			} else {
				Ok({
					kind,
					content_col: marker_end + spaces,
					content_start: pos + marker_end + spaces,
				})
			}
		}
	}
}

## markdown `sameListType`: the same bullet, or the same ordered delimiter.
is_same_list : Marker, Marker -> Bool
is_same_list = |a, b| match (a.kind, b.kind) {
	(Bullet(x), Bullet(y)) => x == y
	(Ordered(x), Ordered(y)) => x.delim == y.delim
	_ => Bool.False
}

## markdown `listInterruptsAt`: a list may interrupt a paragraph when its
## first item is not empty, and an ordered one only when it starts at 1.
is_list_interrupting : List(U8), U64 -> Bool
is_list_interrupting = |md, pos| match list_marker_at(md, pos) {
	Ok(m) =>
		m.content_start < MdText.line_end(md, pos) and match m.kind {
			Ordered(o) => o.start == 1
			Bullet(_) => Bool.True
		}
	Err(NotAMarker) => Bool.False
}

## markdown `renderList`: the whole list from `pos`, its first marker
## `first`. Each item's content is gathered dedented and rendered as blocks
## one level deeper; a blank line between items, or inside one, makes the
## list loose, whose paragraphs keep their `<p>`.
list_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	first : Marker,
	depth : U64,
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
} -> Try(Block, [Hostile])
list_onto = |
	out,
	{
		md,
		pos,
		first,
		depth,
		wrap,
		budget,
	},
| {
	len = List.len(md)
	var $items = []
	var $loose = Bool.False
	var $cur = []
	var $have_item = Bool.False
	var $cur_col = first.content_col
	var $blanks = 0
	var $p = pos
	while $p < len {
		eol = MdText.line_end(md, $p)
		line = MdText.cut(md, { start: $p, end: eol })
		next = MdText.next_line(md, eol)
		if MdText.is_blank(line) {
			$blanks = $blanks + 1
			$p = next
		} else {
			indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 })
			marker = list_marker_at(md, $p)
			match marker {
				Ok(m) if indent < $cur_col => {
					if !is_same_list(m, first) {
						break
					} else {
						{}
					}
					if $have_item {
						$items = List.append($items, $cur)
						$loose = $loose or $blanks > 0
					} else {
						{}
					}
					$have_item = Bool.True
					$cur_col = m.content_col
					$blanks = 0
					$cur = List.append(MdText.cut(md, { start: m.content_start, end: eol }), '\n')
				}
				_ =>
					if indent >= $cur_col and $have_item {
						# An indented line: the item's own, its nested blocks.
						$loose = $loose or $blanks > 0
						$blanks = 0
						$cur = List.append(List.concat($cur, List.drop_first(line, $cur_col)), '\n')
					} else if $blanks == 0 and $have_item and !is_block_start(md, $p) {
						# A lazy continuation of the item's paragraph.
						$cur = List.append(List.concat($cur, line), '\n')
					} else {
						break
					}
			}
			$p = next
		}
	}
	items = if $have_item List.append($items, $cur) else $items
	open = match first.kind {
		Ordered(o) if o.start == 1 => Str.to_utf8("<ol>\n")
		Ordered(o) => Str.to_utf8("<ol start=\"${o.start.to_str()}\">\n")
		Bullet(_) => Str.to_utf8("<ul>\n")
	}
	var $out = List.concat(out, open)
	var $budget = budget
	for item in items {
		# Each item renders into a buffer of its own, so its tight
		# separator sees only its content, not the <li>.
		lead = if $loose or is_first_child_block(item) ['\n'] else []
		inner = blocks_onto({
			out: lead,
			md: item,
			spacing: if $loose Loose else Tight,
			depth: depth + 1,
			wrap,
			budget: $budget,
		})?
		$out = List.join([
			$out,
			Str.to_utf8("<li>"),
			inner.out,
			Str.to_utf8("</li>\n"),
		])
		$budget = inner.budget
	}
	close = match first.kind {
		Ordered(_) => Str.to_utf8("</ol>\n")
		Bullet(_) => Str.to_utf8("</ul>\n")
	}
	Ok({
		out: List.concat($out, close),
		budget: $budget,
		after: $p,
	})
}

## markdown `firstItemChildIsBlock`: a tight item starts on a line of its
## own when its first child is a list, a quote, a fence or a heading, not a
## paragraph.
is_first_child_block : List(U8) -> Bool
is_first_child_block = |item| {
	len = List.len(item)
	var $pos = 0
	while $pos < len {
		eol = MdText.line_end(item, $pos)
		line = MdText.cut(item, { start: $pos, end: eol })
		if !MdText.is_blank(line) {
			return list_marker_at(
				item,
				$pos,
			).is_ok() or is_quote_line(line) or fence_open_at(
				item,
				$pos,
			).is_ok() or atx_heading(line).is_ok()
		} else {
			$pos = MdText.next_line(item, eol)
		}
	}
	Bool.False
}

## markdown `lineStartsBlock`: the line at `pos` starts a block a lazy
## continuation may not take in (a blank line, a list item, a quote, a
## fence, a heading).
is_block_start : List(U8), U64 -> Bool
is_block_start = |md, pos| {
	line = MdText.cut(md, { start: pos, end: MdText.line_end(md, pos) })
	MdText.is_blank(line) or list_marker_at(
		md,
		pos,
	).is_ok() or is_quote_line(line) or fence_open_at(md, pos).is_ok() or atx_heading(line).is_ok()
}

# ── blockquotes ──

## markdown `quoteMarkerLen`: the prefix a quote's line drops: up to three
## spaces, a `>`, and one space after it.
quote_marker_len : List(U8) -> Try(U64, [NotAQuote])
quote_marker_len = |line| {
	indent = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), 4)
	if indent >= 4 or List.get(line, indent) != Ok('>') {
		Err(NotAQuote)
	} else if List.get(line, indent + 1) == Ok(' ') {
		Ok(indent + 2)
	} else {
		Ok(indent + 1)
	}
}

is_quote_line : List(U8) -> Bool
is_quote_line = |line| quote_marker_len(line).is_ok()

## markdown `renderQuote`: the quote from `pos`, its `>` lines (and a
## paragraph's lazy lines, up to a blank one) stripped and rendered as
## blocks one level deeper.
quote_onto : List(U8),
{
	md : List(U8),
	pos : U64,
	depth : U64,
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
} -> Try(Block, [Hostile])
quote_onto = |
	out,
	{
		md,
		pos,
		depth,
		wrap,
		budget,
	},
| {
	len = List.len(md)
	var $inner = []
	var $last_was_text = Bool.False
	var $p = pos
	while $p < len {
		eol = MdText.line_end(md, $p)
		line = MdText.cut(md, { start: $p, end: eol })
		if MdText.is_blank(line) {
			break
		} else {
			{}
		}
		match quote_marker_len(line) {
			Ok(strip) => {
				stripped = List.drop_first(line, strip)
				$inner = List.append(List.concat($inner, stripped), '\n')
				$last_was_text = !MdText.is_blank(stripped) and !is_block_start(md, $p + strip)
			}
			Err(NotAQuote) =>
				if $last_was_text and !is_block_start(md, $p) {
					$inner = List.append(List.concat($inner, line), '\n')
				} else {
					break
				}
		}
		$p = MdText.next_line(md, eol)
	}
	quoted = blocks_onto({
		out: List.concat(out, Str.to_utf8("<blockquote>\n")),
		md: $inner,
		spacing: Loose,
		depth: depth + 1,
		wrap,
		budget,
	})?
	Ok({
		out: List.concat(quoted.out, Str.to_utf8("</blockquote>\n")),
		budget: quoted.budget,
		after: $p,
	})
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

p_open : List(U8)
p_open = Str.to_utf8("<p>")

p_close : List(U8)
p_close = Str.to_utf8("</p>\n")

br : List(U8)
br = Str.to_utf8("<br>\n")

md : Str -> Str
md = |text| Str.from_utf8(Md.render(Str.to_utf8(text))) ?? "not text"

# markdown.zig's own cases.
expect md("<video src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video>") == "<p><video controls preload=\"metadata\" src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video></p>\n"
expect md("hello\nworld") == "<p>hello<br>\nworld</p>\n"
expect md("# about MSG_plans_3") == "<h1>about <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></h1>\n"
expect md("```zig\na<b\n```\nafter") == "<pre><code class=\"language-zig\">a&lt;b\n</code></pre>\n<p>after</p>\n"
expect md("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
expect md("> q\nlazy") == "<blockquote>\n<p>q<br>\nlazy</p>\n</blockquote>\n"
expect Str.from_utf8(Md.render_trusted_reflow(Str.to_utf8("A **bold phrase that\nspans two lines** here."))) == Ok("<p>A <strong>bold phrase that spans two lines</strong> here.</p>\n")
expect Md.hostility(Str.to_utf8("some **bold** text and a [link](http://x.com)")) == Renderable
