## **A LIST** (chat-markdown markdown.zig's `renderList`): a list item's
## marker, which lists continue one another and which may interrupt a
## paragraph, and the list rendered, each item's content gathered dedented
## and rendered as blocks one level deeper. Pure.
##
## **A CONTAINER, SO Md HANDS IN WHAT IT ASKS OF THE DISPATCHER**: Md
## dispatches to a list, and an item's content is blocks again, so an
## import of Md here would be a cycle, which Roc refuses. `list_onto` takes
## the three things it needs from Md as arguments instead: `nested` (an
## item's content as blocks, one level deeper: the depth and the wrap are
## Md's, captured there), `is_block_start` (the lines a lazy one may not be)
## and `is_table_at`. Md stays the one home of each, and a list reads in one
## module.
import Ascii
import Bytes
import MdHtml
import MdText

MdList := [].{

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
	## `first`. Each item's content is gathered dedented, its inner blank lines
	## kept, and rendered as blocks one level deeper; a blank line between
	## items, or inside one, makes the list loose, whose paragraphs keep their
	## `<p>`.
	list_onto : List(U8),
	{
		md : List(U8),
		pos : U64,
		first : Marker,
		budget : MdText.Budget,
		nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
		is_block_start : List(U8), U64 -> Bool,
		is_table_at : List(U8), U64 -> Bool,
	} -> Try(MdText.Block, [Hostile])
	list_onto = |
		out,
		{
			md,
			pos,
			first,
			budget,
			nested,
			is_block_start,
			is_table_at,
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
							# The blank lines before it are the item's too: they
							# part its paragraphs and stay in its fences.
							$loose = $loose or $blanks > 0
							$cur = List.concat($cur, List.repeat('\n', $blanks))
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
			Ordered(o) => MdHtml.ol_open(o.start)
			Bullet(_) => MdHtml.ul_open
		}
		var $out = List.concat(out, open)
		var $budget = budget
		for item in items {
			# Each item renders into a buffer of its own, so its tight
			# separator sees only its content, not the <li>.
			lead = if $loose or is_first_child_block(item, { is_block_start, is_table_at }) ['\n'] else []
			inner = nested({
				out: lead,
				md: item,
				spacing: if $loose Loose else Tight,
				budget: $budget,
			})?
			# Appended in place, `$out` unique and first: a List.join of it
			# copies every byte so far, once an item.
			$out = List.concat($out, MdHtml.li_open)
			$out = List.concat($out, inner.out)
			$out = List.concat($out, MdHtml.li_close)
			$budget = inner.budget
		}
		close = match first.kind {
			Ordered(_) => MdHtml.ol_close
			Bullet(_) => MdHtml.ul_close
		}
		Ok({
			out: List.concat($out, close),
			budget: $budget,
			after: $p,
		})
	}
}

## markdown `sameListType`: the same bullet, or the same ordered delimiter.
is_same_list : MdList.Marker, MdList.Marker -> Bool
is_same_list = |a, b| match (a.kind, b.kind) {
	(Bullet(x), Bullet(y)) => x == y
	(Ordered(x), Ordered(y)) => x.delim == y.delim
	_ => Bool.False
}

## markdown `firstItemChildIsBlock`: a tight item starts on a line of its
## own when its first child is a list, a quote, a fence, a heading or a
## table, not a paragraph: its first line that is not blank starts a block
## (`is_block_start`, which asks the first four in that order) or a table.
is_first_child_block : List(U8), { is_block_start : List(U8), U64 -> Bool, is_table_at : List(U8), U64 -> Bool } -> Bool
is_first_child_block = |item, { is_block_start, is_table_at }| {
	len = List.len(item)
	var $pos = 0
	while $pos < len {
		eol = MdText.line_end(item, $pos)
		line = MdText.cut(item, { start: $pos, end: eol })
		if !MdText.is_blank(line) {
			return is_block_start(item, $pos) or is_table_at(item, $pos)
		} else {
			$pos = MdText.next_line(item, eol)
		}
	}
	Bool.False
}
