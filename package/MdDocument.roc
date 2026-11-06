## What a trusted document has and a chat message doesn't: a caller's hook for
## its fences, ids on its headings, rules and indented code. Md's dispatcher
## asks the hook and marks each heading; this module names the marked ones when
## the render is done, since a name depends on every heading before it, and a
## list's items render apart. Pure.
import Ascii
import Bytes
import MdHtml
import MdSafety
import MdText

MdDocument := [].{

	## A fence as a hook sees it: the first word of its info string, the rest
	## of that string, and its body, less the fence's own indent.
	Fence : {
		tag : List(U8),
		args : List(U8),
		body : List(U8),
	}

	## The caller's answer for a fence. `Html` goes out as it is, unescaped,
	## and `Pass` leaves the fence to render as ordinary code.
	FenceHook : Fence -> [Html(List(U8)), Pass]

	## How a document's render treats a fenced block it doesn't know, and how
	## its `![alt](src)` appears. Neither has a default.
	Options : { fence : FenceHook, images : MdSafety.Images }

	## A heading, for a table of contents. Its `text` is plain and unescaped.
	Heading : {
		level : U64,
		id : List(U8),
		text : List(U8),
	}

	Page : {
		html : List(U8),
		headings : List(Heading),
	}

	## `md` with each line's ending a plain `\n`, so a `\r` reaches no grammar or
	## hook. A lone `\r` inside a line stays.
	with_plain_line_ends : List(U8) -> List(U8)
	with_plain_line_ends = |md| {
		len = md.len()
		var $out = []
		var $i = 0
		while $i < len {
			c = MdText.at(md, $i)
			is_line_end = c == '\r' and ($i + 1 == len or md.get($i + 1) == Ok('\n'))
			$out = if (is_line_end) $out else $out.append(c)
			$i = $i + 1
		}
		$out
	}

	## CommonMark's thematic break: up to three spaces, then three or more of
	## `-`, `*` or `_`, with only spaces and tabs among them.
	is_rule : List(U8) -> Bool
	is_rule = |line| {
		indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 })
		match line.get(indent) {
			Ok(mark) if indent < 4 and (mark == '-' or mark == '*' or mark == '_') => {
				body = MdText.trim_line(line)
				body.count_if(|c| c == mark) >= 3 and body.all(|c| c == mark or c == ' ' or c == '\t')
			}
			_ => Bool.False
		}
	}

	## The line opens or continues an indented code block, where the dispatcher
	## is at a block's start. It can't interrupt a paragraph, so a paragraph
	## never asks this.
	is_indented_code : List(U8) -> Bool
	is_indented_code = |line| code_line(line).is_ok()

	## The indented code block at `line_start`, up to the first line that isn't
	## indented. Blank lines inside it stay, with any spaces past the block's
	## indent, and those after it are not its own.
	indented_code_onto : List(U8), { md : List(U8), line_start : U64, budget : MdText.Budget } -> MdText.Block
	indented_code_onto = |out, { md, line_start, budget }| {
		len = md.len()
		var $body = []
		var $blanks = []
		var $p = line_start
		while $p < len {
			eol = MdText.line_end(md, $p)
			line = MdText.cut(md, { start: $p, end: eol })
			if MdText.is_blank(line) {
				$blanks = $blanks.concat(past_code_indent(line) ?? []).append('\n')
			} else {
				match code_line(line) {
					Ok(code) => {
						$body = $body.concat($blanks).concat(code).append('\n')
						$blanks = []
					}
					Err(NotCode) => break
				}
			}
			$p = MdText.next_line(md, eol)
		}
		{
			out: MdText.escape_onto(out.concat(MdHtml.code_block_open([])), $body).concat(MdHtml.code_block_close),
			budget: MdText.charge(budget, $body.len()),
			after: $p,
		}
	}

	## The render's `html` with every marked heading given its id.
	with_heading_ids : List(U8) -> Page
	with_heading_ids = |html| {
		len = html.len()
		var $out = []
		var $headings = []
		var $ids = Dict.empty()
		var $copied = 0
		var $i = MdText.find_or_end(html, { byte: '<', at: 0 })
		while $i < len {
			match marked_heading_at(html, $i) {
				Ok({ level, content_start, content_end }) => {
					text = MdHtml.plain_text(MdText.cut(html, { start: content_start, end: content_end }))
					given = distinct_id(slug(text), $ids)
					id = given.id
					$out = $out.concat(MdText.cut(html, { start: $copied, end: $i })).concat(MdHtml.heading_open_with_id(level, id))
					$headings = $headings.append({ level, id, text })
					$ids = given.ids
					$copied = content_start
					$i = MdText.find_or_end(html, { byte: '<', at: content_end })
				}
				Err(NotMarked) => {
					$i = MdText.find_or_end(html, { byte: '<', at: $i + 1 })
				}
			}
		}
		{ html: $out.concat(html.drop_first($copied)), headings: $headings }
	}
}

## The line less its first four columns of indent. A blank line is no code.
code_line : List(U8) -> Try(List(U8), [NotCode])
code_line = |line| if (MdText.is_blank(line)) Err(NotCode) else past_code_indent(line)

## The line after four columns of indent. A tab reaches the next multiple of
## four, so spaces before a tab go with it.
past_code_indent : List(U8) -> Try(List(U8), [NotCode])
past_code_indent = |line| {
	spaces = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
	if spaces == 4 {
		Ok(line.drop_first(4))
	} else if line.get(spaces) == Ok('\t') {
		Ok(line.drop_first(spaces + 1))
	} else {
		Err(NotCode)
	}
}

## The mark at `at`, and where its heading's content lies.
marked_heading_at : List(U8), U64 -> Try({ level : U64, content_start : U64, content_end : U64 }, [NotMarked])
marked_heading_at = |html, at| match [1, 2, 3, 4, 5, 6].find_first(|n| MdText.is_prefixed_ignoring_case(html, { at, prefix: MdHtml.heading_mark(n) })) {
	Err(NotFound) => Err(NotMarked)
	Ok(level) => {
		content_start = at + MdHtml.heading_mark(level).len()
		match Bytes.find(html.drop_first(content_start), { needle: MdHtml.heading_close(level) }) {
			Ok(n) => Ok({ level, content_start, content_end: content_start + n })
			Err(NotFound) => Err(NotMarked)
		}
	}
}

## A heading's id: its ASCII letters and digits in lower case, its apostrophes
## gone, as on GitHub, and every other run of bytes one hyphen. A heading with
## no letter or digit is a `section`.
slug : List(U8) -> List(U8)
slug = |text| {
	var $id = []
	for c in text {
		if Ascii.is_alphanumeric(c) {
			$id = $id.append(Ascii.to_lowercase(c))
		} else if c != '\'' and $id != [] and $id.last() != Ok('-') {
			$id = $id.append('-')
		} else {
			{}
		}
	}
	trimmed = Bytes.trim($id, ['-'])
	if (trimmed == []) "section".to_utf8() else trimmed
}

## `base`, or the first of `base-2`, `base-3` and so on that no earlier heading
## has. Each id given is a key of `ids`, whose value is the last number tried
## for that base, so a thousand headings of one name don't each count from 2.
distinct_id : List(U8), Dict(List(U8), U64) -> { id : List(U8), ids : Dict(List(U8), U64) }
distinct_id = |base, ids| match ids.get(base) {
	Err(KeyNotFound) => { id: base, ids: ids.insert(base, 1) }
	Ok(last_tried) => {
		var $n = last_tried + 1
		var $id = base.concat("-${$n.to_str()}".to_utf8())
		while ids.contains($id) {
			$n = $n + 1
			$id = base.concat("-${$n.to_str()}".to_utf8())
		}
		{ id: $id, ids: ids.insert($id, 1).insert(base, $n) }
	}
}

mark : U64, Str -> List(U8)
mark = |level, text| MdHtml.heading_mark(level).concat(text.to_utf8()).concat(MdHtml.heading_close(level))

# Rules: each mark, at and around its limits of length and indent.
expect MdDocument.is_rule("---".to_utf8())
expect MdDocument.is_rule("***".to_utf8())
expect MdDocument.is_rule("___".to_utf8())
expect MdDocument.is_rule("-----".to_utf8())
expect MdDocument.is_rule("   ---".to_utf8())
expect MdDocument.is_rule("- - -".to_utf8())
expect MdDocument.is_rule("*\t*\t*  ".to_utf8())
expect MdDocument.is_rule("---\r".to_utf8())
expect !MdDocument.is_rule("--".to_utf8())
expect !MdDocument.is_rule("    ---".to_utf8())
expect !MdDocument.is_rule("\t---".to_utf8())
expect !MdDocument.is_rule("---x".to_utf8())
expect !MdDocument.is_rule("--*".to_utf8())
expect !MdDocument.is_rule("===".to_utf8())
expect !MdDocument.is_rule("".to_utf8())
expect !MdDocument.is_rule("   ".to_utf8())

# Four columns of indent, in each way of writing them, and three.
expect code_line("    a".to_utf8()) == Ok("a".to_utf8())
expect code_line("      a".to_utf8()) == Ok("  a".to_utf8())
expect code_line("\ta".to_utf8()) == Ok("a".to_utf8())
expect code_line("  \ta".to_utf8()) == Ok("a".to_utf8())
expect code_line("   \t\ta".to_utf8()) == Ok("\ta".to_utf8())
expect code_line("    \ta".to_utf8()) == Ok("\ta".to_utf8())
expect code_line("   a".to_utf8()) == Err(NotCode)
expect code_line("a".to_utf8()) == Err(NotCode)
expect code_line("     ".to_utf8()) == Err(NotCode)
expect code_line("\t".to_utf8()) == Err(NotCode)

expect slug("The sky".to_utf8()) == "the-sky".to_utf8()
expect slug("  What's a *sighting*?".to_utf8()) == "whats-a-sighting".to_utf8()
expect slug("a ' b".to_utf8()) == "a-b".to_utf8()
expect slug("'".to_utf8()) == "section".to_utf8()
expect slug("🔭 Zoom 2".to_utf8()) == "zoom-2".to_utf8()
expect slug("🔭".to_utf8()) == "section".to_utf8()

# Only the code's own indent goes from a blank line inside the block.
expect MdDocument.indented_code_onto([], { md: "    a\n      \n    b\n".to_utf8(), line_start: 0, budget: MdText.unlimited }).out == "<pre><code>a\n  \nb\n</code></pre>\n".to_utf8()

expect MdDocument.with_plain_line_ends("a\r\nb\r".to_utf8()) == "a\nb".to_utf8()
expect MdDocument.with_plain_line_ends("a\rb\n\r\n".to_utf8()) == "a\rb\n\n".to_utf8()
expect MdDocument.with_plain_line_ends("\r".to_utf8()) == []

# The third heading's own name is the second's, and stays distinct.
expect MdDocument.with_heading_ids(mark(1, "A").concat(mark(2, "A")).concat(mark(2, "A 2")).concat(mark(2, "A"))).headings.map(|h| h.id) == ["a".to_utf8(), "a-2".to_utf8(), "a-2-2".to_utf8(), "a-3".to_utf8()]
# Headings of one name count up.
expect MdDocument.with_heading_ids(List.repeat(mark(1, "A"), 10).join()).headings.last().map_ok(|h| h.id) == Ok("a-10".to_utf8())
expect MdDocument.with_heading_ids(mark(2, "a &amp; <code>b</code>")) == {
	html: "<h2 id=\"a-b\">a &amp; <code>b</code></h2>\n".to_utf8(),
	headings: [{ level: 2, id: "a-b".to_utf8(), text: "a & b".to_utf8() }],
}
# Only a mark is a heading here: any other tag, and an unclosed mark, stay.
expect MdDocument.with_heading_ids("<h2>a</h2>\n<h2 id=\"\">b</h2>\n<p>b</p>\n<h3 id=\"\">".to_utf8()) == { html: "<h2>a</h2>\n<h2 id=\"\">b</h2>\n<p>b</p>\n<h3 id=\"\">".to_utf8(), headings: [] }
expect MdDocument.with_heading_ids(MdHtml.heading_mark(3)) == { html: MdHtml.heading_mark(3), headings: [] }
