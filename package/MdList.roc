## A list: an item's marker, which lists continue one another and which may
## interrupt a paragraph, and the list rendered, each item's content gathered
## dedented and rendered as blocks one level deeper. Pure.
##
## An item's content is blocks again, so an import of MdBlocks here would be a
## cycle, which Roc refuses. `list_onto` takes what it needs from there as
## arguments: `nested` (an item's content as blocks, one level deeper),
## `is_block_start` (the lines a lazy one may not be), the two questions only a
## document answers yes to, `is_rule` and `is_code`, and how it reads an indent.
import Ascii
import Bytes
import MdHtml
import MdIndent
import MdTable
import MdText

MdList := [].{

	Kind : [Bullet(U8), Ordered({ start : U64, delim : U8 })]

	## A list item's marker: its kind, the column its content starts at (the
	## item's indent), and what its own line holds of that content.
	Marker : {
		kind : Kind,
		content_column : U64,
		first_line : List(U8),
	}

	## Up to three spaces, then `-`, `+`, `*`, or up to
	## nine digits and `.` or `)`, then a space, a tab or the line's end. One
	## to four spaces after are the content's indent; more is one, the rest the
	## content's.
	list_marker_at : List(U8),
	{
		line_start : U64,
		reading : MdIndent.Reading,
	} -> Try(Marker, [NotAMarker])
	list_marker_at = |md, { line_start, reading }| {
		line = MdText.cut(md, { start: line_start, end: MdText.line_end(md, line_start) })
		n = line.len()
		indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
		if indent >= 4 or indent >= n {
			Err(NotAMarker)
		} else {
			c = MdText.at(line, indent)
			found =
				if c == '-' or c == '+' or c == '*' {
					Ok({ kind: Bullet(c), marker_end: indent + 1 })
				} else if Ascii.is_digit(c) {
					digits_end = Bytes.count_while(
						line,
						{ keep: Ascii.is_digit, at: indent },
					).min(indent + 9)
					match line.get(digits_end) {
						Ok(delim) if delim == '.' or delim == ')' => {
							start = MdText.cut(line, { start: indent, end: digits_end }).fold(
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
			after = line.get(marker_end)
			if after != Err(OutOfBounds) and after != Ok(' ') and after != Ok('\t') {
				Err(NotAMarker)
			} else {
				Ok(
					match reading {
						Spaces => spaced_marker(line, { kind, marker_end })
						TabStops => tabbed_marker(line, { kind, marker_end })
					},
				)
			}
		}
	}

	## A list may interrupt a paragraph when its
	## first item is not empty, and an ordered one only when it starts at 1.
	is_list_interrupting : List(U8), { line_start : U64, reading : MdIndent.Reading } -> Bool
	is_list_interrupting = |md, place| match list_marker_at(md, place) {
		Ok(m) =>
			m.first_line != [] and match m.kind {
				Ordered(o) => o.start == 1
				Bullet(_) => Bool.True
			}
		Err(NotAMarker) => Bool.False
	}

	## The whole list from `line_start`, its first marker
	## `first`. Each item's content is gathered dedented, its inner blank lines
	## kept, and rendered as blocks one level deeper; a blank line between
	## items, or inside one, makes the list loose, whose paragraphs keep their
	## `<p>`.
	list_onto : List(U8),
	{
		md : List(U8),
		line_start : U64,
		first : Marker,
		budget : MdText.Budget,
		nested : MdText.Nested -> Try(MdText.Rendered, [Hostile]),
		is_block_start : List(U8), U64 -> Bool,
		is_rule : List(U8) -> Bool,
		is_code : List(U8) -> Bool,
		reading : MdIndent.Reading,
	} -> Try(MdText.Block, [Hostile])
	list_onto = |
		out,
		{
			md,
			line_start,
			first,
			budget,
			nested,
			is_block_start,
			is_rule,
			is_code,
			reading,
		},
	| {
		len = md.len()
		var $items = []
		var $loose = Bool.False
		var $cur = []
		var $have_item = Bool.False
		var $cur_column = first.content_column
		var $blanks = 0
		var $p = line_start
		while $p < len {
			eol = MdText.line_end(md, $p)
			line = MdText.cut(md, { start: $p, end: eol })
			next = MdText.next_line(md, eol)
			if MdText.is_blank(line) {
				$blanks = $blanks + 1
				$p = next
			} else {
				indent = MdIndent.columns_of(line, reading)
				marker = list_marker_at(md, { line_start: $p, reading })
				match marker {
					Ok(m) if indent < $cur_column => {
						# `- - -` reads as a marker too, and a rule outranks one.
						if !is_same_list(m, first) or is_rule(line) {
							break
						} else {
							{}
						}
						if $have_item {
							$items = $items.append($cur)
							$loose = $loose or $blanks > 0
						} else {
							{}
						}
						$have_item = Bool.True
						$cur_column = m.content_column
						$blanks = 0
						$cur = m.first_line.append('\n')
					}
					_ =>
						if indent >= $cur_column and $have_item {
							# An indented line: the item's own, its nested blocks.
							# The blank lines before it are the item's too: they
							# part its paragraphs and stay in its fences.
							$loose = $loose or $blanks > 0
							$cur = $cur.concat(List.repeat('\n', $blanks))
							$blanks = 0
							$cur = $cur.concat(
								MdIndent.without_columns(
									line,
									{ columns: $cur_column, from: 0, reading },
								),
							).append('\n')
						} else if $blanks == 0 and $have_item and !is_block_start(md, $p) {
							# A lazy continuation of the item's paragraph.
							$cur = $cur.concat(line).append('\n')
						} else {
							break
						}
				}
				$p = next
			}
		}
		items = if $have_item {
			$items.append($cur)
		} else {
			$items
		}
		open = match first.kind {
			Ordered(o) => MdHtml.ol_open(o.start)
			Bullet(_) => MdHtml.ul_open
		}
		var $out = out.concat(open)
		var $budget = budget
		for item in items {
			# Each item renders into a buffer of its own, so its tight
			# separator sees only its content, not the <li>.
			lead = if $loose or is_first_child_block(item, { is_block_start, is_code }) {
				['\n']
			} else {
				[]
			}
			inner = nested({
				out: lead,
				md: item,
				spacing: if $loose {
					Loose
				} else {
					Tight
				},
				budget: $budget,
			})?
			# Appended in place, `$out` unique and first: a List.join of it
			# copies every byte so far, once an item.
			$out = $out.concat(MdHtml.li_open)
			$out = $out.concat(inner.out)
			$out = $out.concat(MdHtml.li_close)
			$budget = inner.budget
		}
		close = match first.kind {
			Ordered(_) => MdHtml.ol_close
			Bullet(_) => MdHtml.ul_close
		}
		Ok({
			out: $out.concat(close),
			budget: $budget,
			after: $p,
		})
	}
}

## A chat's marker: one to four spaces after it are the content's indent, and
## with more, or a tab, its content is what follows one space.
spaced_marker : List(U8), { kind : MdList.Kind, marker_end : U64 } -> MdList.Marker
spaced_marker = |line, { kind, marker_end }| {
	spaces = Bytes.count_while(line, { keep: |s| s == ' ', at: marker_end }) - marker_end
	if marker_end >= line.len() {
		{ kind, content_column: marker_end + 1, first_line: [] }
	} else if spaces == 0 or spaces > 4 {
		{
			kind,
			content_column: marker_end + 1,
			first_line: line.drop_first(
				marker_end + (
					if spaces == 0 {
						0
					} else {
						1
					}
				),
			),
		}
	} else {
		{
			kind,
			content_column: marker_end + spaces,
			first_line: line.drop_first(marker_end + spaces),
		}
	}
}

## A document's marker, the same rule in columns, so a tab after it is the indent
## it reaches. A line with nothing after the marker is an empty item.
tabbed_marker : List(U8), { kind : MdList.Kind, marker_end : U64 } -> MdList.Marker
tabbed_marker = |line, { kind, marker_end }| {
	rest = line.drop_first(marker_end)
	reached = MdIndent.column_after_indent(rest, { at: 0, column: marker_end })
	if MdText.is_blank(rest) {
		{ kind, content_column: marker_end + 1, first_line: [] }
	} else if reached > marker_end + 4 {
		{
			kind,
			content_column: marker_end + 1,
			first_line: MdIndent.without_columns(
				rest,
				{
					columns: 1,
					from: marker_end,
					reading: TabStops,
				},
			),
		}
	} else {
		{
			kind,
			content_column: reached,
			first_line: MdIndent.without_columns(
				rest,
				{
					columns: reached - marker_end,
					from: marker_end,
					reading: TabStops,
				},
			),
		}
	}
}

## The same bullet, or the same ordered delimiter.
is_same_list : MdList.Marker, MdList.Marker -> Bool
is_same_list = |a, b| match (a.kind, b.kind) {
	(Bullet(x), Bullet(y)) => x == y
	(Ordered(x), Ordered(y)) => x.delim == y.delim
	_ => Bool.False
}

## A tight item starts on a line of its
## own when its first child is a list, a quote, a fence, a heading, a table
## or indented code, not a paragraph: its first line that is not blank starts
## a block (`is_block_start`, which asks the first four in that order), a table
## or code.
is_first_child_block : List(U8),
{
	is_block_start : List(U8), U64 -> Bool,
	is_code : List(U8) -> Bool,
} -> Bool
is_first_child_block = |item, { is_block_start, is_code }| {
	len = item.len()
	var $line_start = 0
	while $line_start < len {
		eol = MdText.line_end(item, $line_start)
		line = MdText.cut(item, { start: $line_start, end: eol })
		if !MdText.is_blank(line) {
			return is_block_start(
				item,
				$line_start,
			) or MdTable.is_table_at(item, $line_start) or is_code(line)
		} else {
			$line_start = MdText.next_line(item, eol)
		}
	}
	Bool.False
}
