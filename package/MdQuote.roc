## **A BLOCKQUOTE** (chat-markdown markdown.zig's `renderQuote`): where a
## quote's line starts, and the quote rendered, its `>` lines (and a
## paragraph's lazy lines) stripped and rendered as blocks one level deeper.
## Pure.
##
## **A CONTAINER, SO Md HANDS IN WHAT IT ASKS OF THE DISPATCHER**: Md
## dispatches to a quote, and a quote's content is blocks again, so an
## import of Md here would be a cycle, which Roc refuses. `quote_onto` takes
## the three things it needs from Md as arguments instead: `nested` (its
## content as blocks, one level deeper: the depth and the wrap are Md's,
## captured there), `is_block_start` (the lines a lazy one may not be) and
## `is_table_at`. Md stays the one home of each, and a quote reads in one
## module.
import Bytes
import MdHtml
import MdText

MdQuote := [].{

	## The line starts a quote: up to three spaces and a `>`.
	is_quote_line : List(U8) -> Bool
	is_quote_line = |line| quote_marker_len(line).is_ok()

	## markdown `renderQuote`: the quote from `pos`, its `>` lines (and a
	## paragraph's lazy lines, up to a blank one) stripped and rendered as
	## blocks one level deeper.
	quote_onto : List(U8),
	{
		md : List(U8),
		pos : U64,
		budget : MdText.Budget,
		nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
		is_block_start : List(U8), U64 -> Bool,
		is_table_at : List(U8), U64 -> Bool,
	} -> Try(MdText.Block, [Hostile])
	quote_onto = |
		out,
		{
			md,
			pos,
			budget,
			nested,
			is_block_start,
			is_table_at,
		},
	| {
		len = List.len(md)
		var $inner = []
		var $last_was_text = Bool.False
		# A table's rows are no paragraph's, so no line is lazy after them:
		# the table is open from its delimiter row to a blank line or a block.
		var $in_table = Bool.False
		var $prev_start = 0
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
					start = List.len($inner)
					$inner = List.append(List.concat($inner, stripped), '\n')
					ends_text = MdText.is_blank(stripped) or is_block_start(md, $p + strip)
					$in_table = !ends_text and ($in_table or ($last_was_text and is_table_at($inner, $prev_start)))
					$last_was_text = !ends_text and !$in_table
					$prev_start = start
				}
				Err(NotAQuote) =>
					if $last_was_text and !is_block_start(md, $p) {
						$prev_start = List.len($inner)
						$inner = List.append(List.concat($inner, line), '\n')
					} else {
						break
					}
			}
			$p = MdText.next_line(md, eol)
		}
		quoted = nested({
			out: List.concat(out, MdHtml.blockquote_open),
			md: $inner,
			spacing: Loose,
			budget,
		})?
		Ok({
			out: List.concat(quoted.out, MdHtml.blockquote_close),
			budget: quoted.budget,
			after: $p,
		})
	}
}

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
