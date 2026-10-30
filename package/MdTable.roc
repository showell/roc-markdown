## **GFM'S PIPE TABLES, A LINE AT A TIME**: where a
## table stands, a row's cells and the delimiter row's alignments, as the GFM
## spec's "Tables (extension)" reads them. Md's dispatcher, MdList and
## MdQuote ask here where a table opens; Md renders it. Pure.
import MdText

MdTable := [].{

	## A column's alignment, from its delimiter cell's colons: none, `:-`,
	## `:-:`, `-:`.
	Align : [Plain, Left, Center, Right]

	## A row's cells: the line trimmed, a leading `|` and a trailing one
	## dropped, and split at every `|` no backslash escapes. A code span
	## does not hide one (GFM splits first: write `\|` inside it). Each cell
	## is trimmed, and its `\|` is a `|` before its inlines are read. One
	## pass.
	cells : List(U8) -> List(List(U8))
	cells = |line| {
		t = MdText.trim_line(line)
		len = t.len()
		var $cells = []
		var $cell = []
		var $after_pipe = Bool.False
		var $i = if t.first() == Ok('|') 1 else 0
		while $i < len {
			c = MdText.at(t, $i)
			$after_pipe = Bool.False
			if c == '\\' and t.get($i + 1) == Ok('|') {
				$cell = $cell.append('|')
				$i = $i + 2
			} else if c == '\\' and $i + 1 < len {
				$cell = List.concat($cell, [c, MdText.at(t, $i + 1)])
				$i = $i + 2
			} else if c == '|' {
				$cells = List.append($cells, MdText.trim_line($cell))
				$cell = []
				$after_pipe = Bool.True
				$i = $i + 1
			} else {
				$cell = $cell.append(c)
				$i = $i + 1
			}
		}
		# A trailing `|` closes the last cell; it opens none.
		if $after_pipe $cells else List.append($cells, MdText.trim_line($cell))
	}

	## GFM's table at the line at `pos`: that line is its header row and the
	## next a delimiter row of as many cells. Its header's cells, each
	## column's alignment, and where its body starts.
	Table : {
		header : List(List(U8)),
		aligns : List(Align),
		body : U64,
	}

	table_at : List(U8), U64 -> Try(Table, [NotATable])
	table_at = |md, pos| {
		eol = MdText.line_end(md, pos)
		if eol >= md.len() {
			Err(NotATable)
		} else {
			delim_end = MdText.line_end(md, eol + 1)
			match delimiter_row(MdText.cut(md, { start: eol + 1, end: delim_end })) {
				Err(NotADelimiter) => Err(NotATable)
				Ok(aligns) => {
					header = cells(MdText.cut(md, { start: pos, end: eol }))
					if header.len() == aligns.len() {
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

	## The delimiter row: a `|` somewhere (so a line of dashes alone is no
	## delimiter), and every cell one `-` or more, a `:` before them, after
	## them or both. Its alignments, a column each.
	delimiter_row : List(U8) -> Try(List(Align), [NotADelimiter])
	delimiter_row = |line|
		if !line.contains('|') {
			Err(NotADelimiter)
		} else {
			var $aligns = []
			for cell in cells(line) {
				$aligns = $aligns.append(delimiter_cell(cell)?)
			}
			Ok($aligns)
		}
}

delimiter_cell : List(U8) -> Try(MdTable.Align, [NotADelimiter])
delimiter_cell = |cell| {
	n = cell.len()
	left = cell.first() == Ok(':')
	l = if left 1 else 0
	right = n > l and cell.last() == Ok(':')
	r = if right 1 else 0
	dashes = cell.sublist({ start: l, len: n - l - r })
	if dashes == [] or !dashes.all(|c| c == '-') {
		Err(NotADelimiter)
	} else if left and right {
		Ok(Center)
	} else if left {
		Ok(Left)
	} else if right {
		Ok(Right)
	} else {
		Ok(Plain)
	}
}

cells_of : Str -> List(Str)
cells_of = |line| List.map(MdTable.cells(Str.to_utf8(line)), |c| Str.from_utf8(c) ?? "not text")

expect cells_of("| a | b |") == ["a", "b"]
expect cells_of("a | b") == ["a", "b"]
expect cells_of("| a | |") == ["a", ""]
expect cells_of("|") == [""]
expect cells_of("bar") == ["bar"]
expect cells_of("| f\\|oo | `\\|` |") == ["f|oo", "`|`"]
expect cells_of("a \\\\| b") == ["a \\\\", "b"]
expect cells_of("a \\") == ["a \\"]
expect MdTable.delimiter_row("| --- | :-- | :-: | --: |".to_utf8()) == Ok([Plain, Left, Center, Right])
expect MdTable.delimiter_row(":-: | -----------:".to_utf8()) == Ok([Center, Right])
expect MdTable.delimiter_row("---".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row("| : |".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row("| -- | x |".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row("|---||".to_utf8()) == Err(NotADelimiter)
