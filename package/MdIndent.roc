## How a line's indent reads. A chat counts spaces alone, as its frozen answers
## do. A document reads a tab as CommonMark does, up to the next stop of four
## columns, so an indent written with tabs nests as one written with spaces. Pure.
import Bytes

MdIndent := [].{

	Reading : [Spaces, TabStops]

	## The columns of indent `line` starts with.
	columns_of : List(U8), Reading -> U64
	columns_of = |line, reading| match reading {
		Spaces => Bytes.count_while(line, { keep: |c| c == ' ', at: 0 })
		TabStops => column_after_indent(line, { at: 0, column: 0 })
	}

	## `text` less its first `columns` columns of indent, for text that starts at
	## column `from`, and `text` is known to have them. A tab the cut falls inside
	## is a tab no longer: the columns it has left are spaces, and so are the
	## tabs after it, whose stops the cut would otherwise move. A tab the cut
	## doesn't touch stays, so a fence's tabs reach the page.
	without_columns : List(U8), { columns : U64, from : U64, reading : Reading } -> List(U8)
	without_columns = |text, { columns, from, reading }| match reading {
		Spaces => text.drop_first(columns)
		TabStops => {
			end = from + columns
			var $column = from
			var $i = 0
			while $column < end {
				if text.get($i) == Ok('\t') and next_stop($column) > end {
					rest = indent_end(text, $i)
					spaces = column_after_indent(text, { at: $i, column: $column }) - end
					return List.repeat(' ', spaces).concat(text.drop_first(rest))
				} else {
					$column = if (text.get($i) == Ok('\t')) next_stop($column) else $column + 1
					$i = $i + 1
				}
			}
			text.drop_first($i)
		}
	}

	## The column the indent of `text`, from byte `at` at column `column`, reaches.
	column_after_indent : List(U8), { at : U64, column : U64 } -> U64
	column_after_indent = |text, { at, column }| match text.get(at) {
		Ok(' ') => column_after_indent(text, { at: at + 1, column: column + 1 })
		Ok('\t') => column_after_indent(text, { at: at + 1, column: next_stop(column) })
		_ => column
	}
}

next_stop : U64 -> U64
next_stop = |column| (column // tab_stop + 1) * tab_stop

tab_stop : U64
tab_stop = 4

indent_end : List(U8), U64 -> U64
indent_end = |text, at| Bytes.count_while(text, { keep: |c| c == ' ' or c == '\t', at })

columns : Str -> U64
columns = |line| MdIndent.columns_of(line.to_utf8(), TabStops)

cut : Str, { columns : U64, from : U64 } -> Str
cut = |line, { columns: n, from }| Str.from_utf8(MdIndent.without_columns(line.to_utf8(), { columns: n, from, reading: TabStops })) ?? crash "MdIndent: a test's text is UTF-8"

expect columns("a") == 0
expect columns("  a") == 2
expect columns("\ta") == 4
expect columns("  \ta") == 4
expect columns("    \ta") == 8
expect columns("\t\t a") == 9
expect MdIndent.columns_of("\ta".to_utf8(), Spaces) == 0
expect MdIndent.columns_of("  \ta".to_utf8(), Spaces) == 2

expect cut("    a", { columns: 2, from: 0 }) == "  a"
expect cut("\ta", { columns: 4, from: 0 }) == "a"
# The cut falls inside a tab: what's left of it, and the tab after, are spaces.
expect cut("\ta", { columns: 2, from: 0 }) == "  a"
expect cut("\t\ta", { columns: 2, from: 0 }) == "      a"
# A tab past the cut stays.
expect cut("  \ta", { columns: 2, from: 0 }) == "\ta"
expect cut("\t\ta", { columns: 4, from: 0 }) == "\ta"
# After `>` at column 0 the text starts at column 1, and the tab reaches column 4.
expect cut("\ta", { columns: 1, from: 1 }) == "  a"
expect cut("\t\ta", { columns: 1, from: 1 }) == "      a"
expect cut(" a", { columns: 1, from: 1 }) == "a"
expect MdIndent.without_columns("\ta".to_utf8(), { columns: 1, from: 0, reading: Spaces }) == "a".to_utf8()
