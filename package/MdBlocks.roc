## The block dispatcher: a text's blocks, in order, onto the output. Lists and
## quotes are modules of their own whose content is blocks again, so
## `blocks_onto` hands each the recursion (`nested`) and the questions it asks
## about block starts, since an import of this module there would be a cycle. A
## new block kind is a branch of `block_at`, and a line of `is_block_start` and
## of `paragraph_onto`'s stop when it interrupts a paragraph. Pure.
import Bytes
import MdDialect
import MdDocument
import MdFence
import MdHeading
import MdHtml
import MdInline
import MdList
import MdQuote
import MdRawHtml
import MdSafety
import MdTable
import MdTableBlock
import MdText

MdBlocks := [].{

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
		dialect : MdDialect.Dialect,
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
			start = if out != [] and out.last() != Ok('\n') {
				out.append('\n')
			} else {
				out
			}
			flat = MdInline.render_onto({
				out: start.concat(MdHtml.p_open),
				text: md,
				refs: MdDialect.inline_refs(dialect),
				budget,
				uploads,
			})?
			Ok({ out: flat.out.concat(MdHtml.p_close), budget: flat.budget })
		} else {
			len = md.len()
			# A container's content is blocks one level deeper, in this render's
			# wrap: the recursion MdList and MdQuote are handed, so they need no
			# import of this module (a cycle) and the depth stays here.
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
			var $line_start = 0
			while $line_start < len {
				$budget = MdText.charge($budget, 1)
				if MdText.is_blown($budget) {
					return Err(Hostile)
				} else {
					{}
				}
				eol = MdText.line_end(md, $line_start)
				line = MdText.cut(md, { start: $line_start, end: eol })
				next = MdText.next_line(md, eol)
				if MdText.is_blank(line) {
					$line_start = next
				} else {
					block = block_at(
						tight_sep($out, spacing),
						{
							md,
							line_start: $line_start,
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
					$line_start = block.after
				}
			}
			Ok({ out: $out, budget: $budget })
		}
}

## Quotes and lists nest at most this deep;
## past it, the rest renders as one paragraph. Ordinary conversation never
## nests past about 10 (Steve, 2026-06-19).
max_block_depth : U64
max_block_depth = 16

## The block at `line_start` (its line `line`, the line after it at `next`) onto
## `out`, already separated from the block before: the dispatcher's one
## question, its blocks in the order they are asked. A document's indented code
## and rule come first: nothing else claims four columns of indent, and `- - -`
## would read as a list. A fence, a heading, a list and a quote can each
## interrupt a paragraph, so each is asked next; then an HTML block and a table;
## else a paragraph.
block_at : List(U8),
{
	md : List(U8),
	line_start : U64,
	line : List(U8),
	next : U64,
	spacing : [Tight, Loose],
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> Try(MdText.Block, [Hostile])
block_at = |
	out,
	{
		md,
		line_start,
		line,
		next,
		spacing,
		wrap,
		budget,
		nested,
		uploads,
		dialect,
	},
| {
	is_rule = |text| MdDialect.is_rule(dialect, text)
	is_code = |text| MdDialect.is_code(dialect, text)
	starts_block = |text, start| is_block_start(dialect, { md: text, line_start: start })
	reading = MdDialect.indent_reading(dialect)
	is_raw_html = MdRawHtml.is_html_block_start(line) and !MdDialect.is_angle_url_line(
		dialect,
		line,
	)
	if is_code(line) {
		Ok(MdDocument.indented_code_onto(out, { md, line_start, budget }))
	} else if is_rule(line) {
		Ok({
			out: out.concat(MdHtml.hr),
			budget,
			after: next,
		})
	} else {
		match MdFence.open_at(md, line_start) {
			Ok(open) => Ok(MdFence.fence_onto(out, { md, open, line, budget, dialect }))
			Err(NotAFence) =>
				match MdHeading.atx_heading(line) {
					Ok(h) => MdHeading.heading_onto(
						out,
						{
							level: h.level,
							content: h.content,
							after: next,
							budget,
							uploads,
							dialect,
						},
					)
					Err(NotAHeading) =>
						match MdList.list_marker_at(md, { line_start, reading }) {
							Ok(marker) => MdList.list_onto(
								out,
								{
									md,
									line_start,
									first: marker,
									budget,
									nested,
									is_block_start: starts_block,
									is_rule,
									is_code,
									reading,
								},
							)
							Err(NotAMarker) =>
								if MdQuote.is_quote_line(line) {
									MdQuote.quote_onto(
										out,
										{
											md,
											line_start,
											budget,
											nested,
											is_block_start: starts_block,
											is_code,
											reading,
										},
									)
								} else if is_raw_html {
									Ok(
										MdRawHtml.raw_html_onto(
											out,
											{ md, line_start, budget, uploads },
										),
									)
								} else if MdTable.is_table_at(md, line_start) {
									MdTableBlock.table_onto(
										out,
										{
											md,
											line_start,
											budget,
											uploads,
											dialect,
											ends_table: |
												text,
												row,
											| starts_block(text, row) or is_code(
												MdText.cut(
													text,
													{ start: row, end: MdText.line_end(text, row) },
												),
											),
										},
									)
								} else {
									paragraph_onto(
										out,
										{
											md,
											line_start,
											spacing,
											wrap,
											budget,
											uploads,
											dialect,
										},
									)
								}
						}
				}
		}
	}
}

## A paragraph: the longest run of lines that are not blank and start no
## block that may interrupt one. Indented code can't, so an indented line after
## a paragraph's first is that paragraph's. In the hard-wrap dialect each line is
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
	line_start : U64,
	spacing : [Tight, Loose],
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> Try(MdText.Block, [Hostile])
paragraph_onto = |
	out,
	{
		md,
		line_start,
		spacing,
		wrap,
		budget,
		uploads,
		dialect,
	},
| {
	len = md.len()
	var $lines = []
	var $p = line_start
	while $p < len {
		eol = MdText.line_end(md, $p)
		line = MdText.cut(md, { start: $p, end: eol })
		is_interrupted = MdFence.open_at(md, $p).is_ok()
			or MdHeading.atx_heading(line).is_ok()
			or MdList.is_list_interrupting(
				md,
				{ line_start: $p, reading: MdDialect.indent_reading(dialect) },
			)
			or MdQuote.is_quote_line(line)
			or ($p > line_start and MdTable.is_table_at(md, $p))
			or MdDialect.is_rule(dialect, line)
		if MdText.is_blank(line) or is_interrupted {
			break
		} else {
			{}
		}
		$lines = $lines.append(line)
		$p = MdText.next_line(md, eol)
	}
	last = $lines.len() - 1
	var $out = if spacing == Tight {
		out
	} else {
		out.concat(MdHtml.p_open)
	}
	var $budget = budget
	var $reflow = []
	var $k = 0
	for line in $lines {
		breaks = $k < last and ends_in_hard_break(line)
		text = MdText.trim_line(
			if breaks {
				line.drop_last(1)
			} else {
				line
			},
		)
		if wrap == Reflow {
			$reflow = (
				if $reflow == [] {
					$reflow
				} else {
					$reflow.append(' ')
				}
			).concat(text)
			if breaks {
				broke = MdInline.render_onto({
					out: $out,
					text: $reflow,
					refs: MdDialect.inline_refs(dialect),
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
				out: if $k == 0 {
					$out
				} else {
					$out.concat(MdHtml.br)
				},
				text,
				refs: MdDialect.inline_refs(dialect),
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
			refs: MdDialect.inline_refs(dialect),
			budget: $budget,
			uploads,
		})?
		$out = joined.out
		$budget = joined.budget
	} else {
		{}
	}
	Ok({
		out: if spacing == Tight {
			$out
		} else {
			$out.concat(MdHtml.p_close)
		},
		budget: $budget,
		after: $p,
	})
}

## CommonMark's hard line break: the line, as written, ends in an odd run of
## backslashes (an even one is escaped backslashes).
ends_in_hard_break : List(U8) -> Bool
ends_in_hard_break = |line| Bytes.count_back(line, |c| c == '\\') % 2 == 1

## Inside a tight list item, a block after a bare
## paragraph starts on a line of its own.
tight_sep : List(U8), [Tight, Loose] -> List(U8)
tight_sep = |out, spacing|
	if spacing == Tight and out != [] and out.last() != Ok('\n') {
		out.append('\n')
	} else {
		out
	}

# ── block starts ──

## The line at `line_start` starts a block a lazy
## continuation may not take in (a blank line, a list item, a quote, a
## fence, a heading, and in a document a rule).
is_block_start : MdDialect.Dialect, { md : List(U8), line_start : U64 } -> Bool
is_block_start = |dialect, { md, line_start }| {
	line = MdText.cut(md, { start: line_start, end: MdText.line_end(md, line_start) })
	reading = MdDialect.indent_reading(dialect)
	MdText.is_blank(line)
		or MdList.list_marker_at(md, { line_start, reading }).is_ok()
		or MdQuote.is_quote_line(line)
		or MdFence.open_at(md, line_start).is_ok()
		or MdHeading.atx_heading(line).is_ok()
		or MdDialect.is_rule(dialect, line)
}
