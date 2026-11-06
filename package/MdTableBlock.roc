## A GFM table rendered. Its grammar is MdTable's, and this module is apart from
## it because MdHtml reads MdTable's alignments. Pure.
import MdDialect
import MdHtml
import MdInline
import MdSafety
import MdTable
import MdText

MdTableBlock := [].{

	## GFM's table from `pos` (MdTable `table_at`): its header row in `<thead>`, then a body row a
	## line, up to a blank line or one that starts a block (is_block_start),
	## each cut or padded to the header's width with empty cells. No body, no
	## `<tbody>`. A unit a row and a unit a cell, checked a cell: a short row's
	## padding is output its source never paid for.
	table_onto : List(U8),
	{
		md : List(U8),
		pos : U64,
		budget : MdText.Budget,
		uploads : MdSafety.Uploads,
		dialect : MdDialect.Dialect,
		is_block_start : List(U8), U64 -> Bool,
	} -> Try(MdText.Block, [Hostile])
	table_onto = |out, { md, pos, budget, uploads, dialect, is_block_start }| match MdTable.table_at(md, pos) {
		Err(NotATable) => crash "MdTableBlock.table_onto: no table where the dispatcher found one"
		Ok(table) => {
			len = md.len()
			head = row_onto(
				out.concat(MdHtml.table_open),
				{ cells: table.header, aligns: table.aligns, tag: Th, budget, uploads, dialect },
			)?
			var $out = head.out.concat(MdHtml.thead_close)
			var $budget = head.budget
			var $rows = 0
			var $p = table.body
			while $p < len and !is_block_start(md, $p) {
				eol = MdText.line_end(md, $p)
				row = row_onto(
					if ($rows == 0) $out.concat(MdHtml.tbody_open) else $out,
					{
						cells: MdTable.cells(MdText.cut(md, { start: $p, end: eol })),
						aligns: table.aligns,
						tag: Td,
						budget: $budget,
						uploads,
						dialect,
					},
				)?
				$out = row.out
				$budget = row.budget
				$rows = $rows + 1
				$p = MdText.next_line(md, eol)
			}
			Ok({
				out: (if ($rows == 0) $out else $out.concat(MdHtml.tbody_close)).concat(MdHtml.table_close),
				budget: $budget,
				after: $p,
			})
		}
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
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> Try(MdText.Rendered, [Hostile])
row_onto = |out, { cells, aligns, tag, budget, uploads, dialect }| {
	var $out = out.concat(MdHtml.tr_open)
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
			out: $out.concat(MdHtml.cell_open(tag, align)),
			text: cells.get($k) ?? [],
			refs: MdDialect.inline_refs(dialect),
			budget: $budget,
			uploads,
		})?
		$out = cell.out.concat(MdHtml.cell_close(tag))
		$budget = cell.budget
		$k = $k + 1
	}
	Ok({ out: $out.concat(MdHtml.tr_close), budget: $budget })
}
