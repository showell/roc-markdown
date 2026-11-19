## **GFM'S PIPE TABLES, A LINE AT A TIME**: where a
## table stands, a row's cells and the delimiter row's alignments, as the GFM
## spec's "Tables (extension)" reads them. MdBlocks' dispatcher, MdList
## and MdQuote ask here where a table opens, and MdTableBlock renders it. Pure.
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
		trimmed = MdText.trim_line(line)
		length = trimmed.len()
		var $cells = []
		var $cell = []
		var $after_pipe = Bool.False
		var $i = if trimmed.first() == Ok('|') {
			1
		} else {
			0
		}
		while $i < length {
			byte = MdText.byte_at(trimmed, $i)
			$after_pipe = Bool.False
			if byte == '\\' and trimmed.get($i + 1) == Ok('|') {
				$cell = $cell.append('|')
				$i = $i + 2
			} else if byte == '\\' and $i + 1 < length {
				$cell = List.concat($cell, [byte, MdText.byte_at(trimmed, $i + 1)])
				$i = $i + 2
			} else if byte == '|' {
				$cells = $cells.append(MdText.trim_line($cell))
				$cell = []
				$after_pipe = Bool.True
				$i = $i + 1
			} else {
				$cell = $cell.append(byte)
				$i = $i + 1
			}
		}
		# A trailing `|` closes the last cell; it opens none.
		if $after_pipe {
			$cells
		} else {
			$cells.append(MdText.trim_line($cell))
		}
	}

	## GFM's table at the line at `line_start`: that line is its header row and the
	## next a delimiter row of as many cells. Its header's cells, each
	## column's alignment, and where its body starts.
	Table : {
		header_cells : List(List(U8)),
		aligns : List(Align),
		body : U64,
	}

	table_at : List(U8), U64 -> Try(Table, [NotATable])
	table_at = |md, line_start| {
		line_end = MdText.line_end(md, line_start)
		if line_end >= md.len() {
			Err(NotATable)
		} else {
			delimiter_row_end = MdText.line_end(md, line_end + 1)
			match delimiter_row_aligns(
				MdText.cut(md, { start: line_end + 1, end: delimiter_row_end }),
			) {
				Err(NotADelimiter) => Err(NotATable)
				Ok(aligns) => {
					header_cells = cells(MdText.cut(md, { start: line_start, end: line_end }))
					if header_cells.len() == aligns.len() {
						Ok({
							header_cells,
							aligns,
							body: MdText.next_line(md, delimiter_row_end),
						})
					} else {
						Err(NotATable)
					}
				}
			}
		}
	}

	is_table_at : List(U8), U64 -> Bool
	is_table_at = |md, line_start| table_at(md, line_start).is_ok()

	## The delimiter row: a `|` somewhere (so a line of dashes alone is no
	## delimiter), and every cell one `-` or more, a `:` before them, after
	## them or both. Its alignments, a column each.
	delimiter_row_aligns : List(U8) -> Try(List(Align), [NotADelimiter])
	delimiter_row_aligns = |line|
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
	length = cell.len()
	left = cell.first() == Ok(':')
	left_width = if left {
		1
	} else {
		0
	}
	right = length > left_width and cell.last() == Ok(':')
	right_width = if right {
		1
	} else {
		0
	}
	dashes = cell.sublist({ start: left_width, len: length - left_width - right_width })
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
cells_of = |line| MdTable.cells(line.to_utf8()).map(|c| Str.from_utf8(c) ?? crash "a test's text is UTF-8")

expect cells_of("| a | b |") == ["a", "b"]
expect cells_of("a | b") == ["a", "b"]
expect cells_of("| a | |") == ["a", ""]
expect cells_of("|") == [""]
expect cells_of("bar") == ["bar"]
expect cells_of("| f\\|oo | `\\|` |") == ["f|oo", "`|`"]
expect cells_of("a \\\\| b") == ["a \\\\", "b"]
expect cells_of("a \\") == ["a \\"]
expect MdTable.delimiter_row_aligns("| --- | :-- | :-: | --: |".to_utf8()) == Ok([
	Plain,
	Left,
	Center,
	Right,
])
expect MdTable.delimiter_row_aligns(":-: | -----------:".to_utf8()) == Ok([Center, Right])
expect MdTable.delimiter_row_aligns("---".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row_aligns("| : |".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row_aligns("| -- | x |".to_utf8()) == Err(NotADelimiter)
expect MdTable.delimiter_row_aligns("|---||".to_utf8()) == Err(NotADelimiter)
