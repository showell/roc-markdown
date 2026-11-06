## A blockquote: where a quote's line starts, and the quote rendered, its `>`
## lines (and a paragraph's lazy lines) stripped and rendered as blocks one level
## deeper. Pure.
##
## A quote's content is blocks again, so an import of MdBlocks here would be a
## cycle, which Roc refuses. `quote_onto` takes what it needs from there as
## arguments: `nested` (its content as blocks, one level deeper),
## `is_block_start` (the lines a lazy one may not be), `is_code`, which only a
## document answers yes to, and how it reads an indent.
import Bytes
import MdHtml
import MdIndent
import MdTable
import MdText

MdQuote := [].{

	## The line starts a quote: up to three spaces and a `>`.
	is_quote_line : List(U8) -> Bool
	is_quote_line = |line| quote_marker_len(line).is_ok()

	## The quote from `line_start`, its `>` lines (and a
	## paragraph's lazy lines, up to a blank one) stripped and rendered as
	## blocks one level deeper.
	quote_onto : List(U8),
	{
		md : List(U8),
		line_start : U64,
		budget : MdText.Budget,
		nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
		is_block_start : List(U8), U64 -> Bool,
		is_code : List(U8) -> Bool,
		reading : MdIndent.Reading,
	} -> Try(MdText.Block, [Hostile])
	quote_onto = |
		out,
		{
			md,
			line_start,
			budget,
			nested,
			is_block_start,
			is_code,
			reading,
		},
	| {
		len = md.len()
		var $inner = []
		var $last_was_text = Bool.False
		# A table's rows are no paragraph's, so no line is lazy after them:
		# the table is open from its delimiter row to a blank line or a block.
		var $in_table = Bool.False
		var $prev_start = 0
		var $p = line_start
		while $p < len {
			eol = MdText.line_end(md, $p)
			line = MdText.cut(md, { start: $p, end: eol })
			if MdText.is_blank(line) {
				break
			} else {
				{}
			}
			match quote_marker_len(line) {
				Ok(marker_end) => {
					stripped = without_marker(line, { marker_end, reading })
					start = $inner.len()
					$inner = $inner.concat(stripped).append('\n')
					# Indented text after a paragraph is that paragraph's, not code.
					starts_code = !$last_was_text and is_code(stripped)
					ends_text = MdText.is_blank(stripped) or is_block_start(
						$inner,
						start,
					) or starts_code
					$in_table = !ends_text and (
						$in_table or (
							$last_was_text and MdTable.is_table_at(
								$inner,
								$prev_start,
							)
						)
					)
					$last_was_text = !ends_text and !$in_table
					$prev_start = start
				}
				Err(NotAQuote) =>
					if $last_was_text and !is_block_start(md, $p) {
						$prev_start = $inner.len()
						$inner = $inner.concat(line).append('\n')
					} else {
						break
					}
			}
			$p = MdText.next_line(md, eol)
		}
		quoted = nested({
			out: out.concat(MdHtml.blockquote_open),
			md: $inner,
			spacing: Loose,
			budget,
		})?
		Ok({
			out: quoted.out.concat(MdHtml.blockquote_close),
			budget: quoted.budget,
			after: $p,
		})
	}
}

## Where a quote's `>` ends: after up to three spaces and the `>`.
quote_marker_len : List(U8) -> Try(U64, [NotAQuote])
quote_marker_len = |line| {
	indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
	if indent >= 4 or line.get(indent) != Ok('>') {
		Err(NotAQuote)
	} else {
		Ok(indent + 1)
	}
}

## The line less its marker and the one column of space after it. In a chat
## that column is a space. In a document a tab is that space too, and the columns
## it has left are the content's indent.
without_marker : List(U8), { marker_end : U64, reading : MdIndent.Reading } -> List(U8)
without_marker = |line, { marker_end, reading }| {
	rest = line.drop_first(marker_end)
	match (rest.first(), reading) {
		(Ok(' '), _) => rest.drop_first(1)
		(Ok('\t'), TabStops) => MdIndent.without_columns(
			rest,
			{ columns: 1, from: marker_end, reading },
		)
		_ => rest
	}
}
