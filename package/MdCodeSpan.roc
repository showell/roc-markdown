## **CODE SPANS**: a backtick run closed by a run of exactly its length, the
## content between them as CommonMark trims it, and the `<code>` it becomes
## (its tags MdHtml's). A span's content is read raw, so a backslash inside one
## stays. A reflowed paragraph's lines are joined here too, as only a code
## span keeps the spaces before a line end. The inline pass (MdInline) finds
## each span from its opening run. Pure.
##
## Every byte a scan reads is charged to the budget.
import Bytes
import MdHtml
import MdText

MdCodeSpan := [].{

	## A reflowed paragraph's lines joined into one line of inline content, as
	## CommonMark joins them. Each line comes with its trailing spaces. A line
	## end outside a code span is one space, the spaces before it dropped. Inside
	## a code span it is a space too, and the spaces before it are the code's.
	## The spans are found as MdInline's `html_onto` finds them, from each backtick run
	## that a backslash does not escape.
	reflow_lines : List(List(U8)) -> List(U8)
	reflow_lines = |lines| {
		var $joined = []
		var $is_first = Bool.True
		for line in lines {
			$joined = if $is_first {
				line
			} else {
				List.concat($joined.append('\n'), line)
			}
			$is_first = Bool.False
		}
		joined = $joined
		length = joined.len()
		var $out = []
		var $i = 0
		while $i < length {
			c = MdText.byte_at(joined, $i)
			if c == '\\' and MdText.is_escapable(joined, $i + 1) {
				$out = List.concat($out, MdText.cut(joined, { start: $i, end: $i + 2 }))
				$i = $i + 2
			} else if c == '`' {
				scanned = MdCodeSpan.span_at(joined, { at: $i, budget: MdText.unlimited })
				end = match scanned.span {
					Ok(span) => span.end
					Err(NoClose) => $i + Bytes.run_length(joined, { byte: '`', at: $i })
				}
				code = MdText.cut(joined, { start: $i, end })
				$out = List.concat($out, code.map(line_end_as_space))
				$i = end
			} else if c == '\n' {
				kept = $out.len() - Bytes.count_back($out, |b| b == ' ' or b == '\t' or b == '\r')
				$out = $out.take_first(kept).append(' ')
				$i = $i + 1
			} else {
				$out = $out.append(c)
				$i = $i + 1
			}
		}
		$out
	}

	## The backtick run at `at` closed by a run of
	## exactly its length, its content's span, and the index past the close.
	span_at : List(U8),
	{ at : U64, budget : MdText.Budget } -> {
		span : Try(
			{
				content_start : U64,
				content_end : U64,
				end : U64,
			},
			[NoClose],
		),
		budget : MdText.Budget,
	}
	span_at = |text, { at, budget }| {
		length = text.len()
		n = Bytes.run_length(text, { byte: '`', at })
		var $budget = MdText.charge(budget, n)
		var $k = at + n
		while $k < length {
			$budget = MdText.charge($budget, 1)
			if MdText.byte_at(text, $k) != '`' {
				$k = $k + 1
			} else {
				m = Bytes.run_length(text, { byte: '`', at: $k })
				$budget = MdText.charge($budget, m)
				if m == n {
					return {
						span: Ok({
							content_start: at + n,
							content_end: $k,
							end: $k + m,
						}),
						budget: $budget,
					}
				} else {
					# A run of the wrong length is content.
					$k = $k + m
				}
			}
		}
		{ span: Err(NoClose), budget: $budget }
	}

	## A code span's html: its content `text[start..end]`, as CommonMark trims
	## it, escaped.
	span_html : List(U8), { start : U64, end : U64 } -> List(U8)
	span_html = |text, span| {
		content = span_content(MdText.cut(text, span))
		List.concat(MdText.escape_onto(MdHtml.code_open, content), MdHtml.code_close)
	}
}

## A code span's line end is a space (CommonMark).
line_end_as_space : U8 -> U8
line_end_as_space = |b|
	if b == '\n' {
		' '
	} else {
		b
	}

## One space off each end when both ends
## are spaces and it is not all spaces.
span_content : List(U8) -> List(U8)
span_content = |content| {
	n = content.len()
	is_padded = content.first() == Ok(' ') and content.last() == Ok(' ')
	if n >= 2 and is_padded and content.any(|c| c != ' ') {
		MdText.cut(content, { start: 1, end: n - 1 })
	} else {
		content
	}
}

# A reflowed line end: one space outside a code span, the code's own inside.
expect MdCodeSpan.reflow_lines(["a  ".to_utf8(), "b".to_utf8()]) == "a b".to_utf8()
expect MdCodeSpan.reflow_lines(["`a  ".to_utf8(), "b`".to_utf8()]) == "`a   b`".to_utf8()
expect MdCodeSpan.reflow_lines(["\\`a  ".to_utf8(), "b`".to_utf8()]) == "\\`a b`".to_utf8()
expect MdCodeSpan.reflow_lines(["``a  ".to_utf8(), "b`".to_utf8()]) == "``a b`".to_utf8()
