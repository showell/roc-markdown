## An ATX heading: where one stands and what it writes. Pure.
import Bytes
import MdDialect
import MdHtml
import MdInline
import MdSafety
import MdText

MdHeading := [].{

	## 1 to 6 `#` after up to three spaces, then a space,
	## a tab or the line's end; a closing run of `#` is no content.
	atx_heading : List(U8) -> Try({ level : U64, content : List(U8) }, [NotAHeading])
	atx_heading = |line| {
		indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
		level_end = Bytes.count_while(line, { keep: |c| c == '#', at: indent })
		level = level_end - indent
		# The marks end the line, or a space or a tab follows them.
		is_ended = match line.get(level_end) {
			Ok(c) => c == ' ' or c == '\t'
			Err(OutOfBounds) => Bool.True
		}
		if indent >= 4 or level == 0 or level > 6 or !is_ended {
			Err(NotAHeading)
		} else {
			content = Bytes.trim(line.drop_first(level_end), heading_space)
			h = content.len() - Bytes.count_back(content, |c| c == '#')
			closed =
				if h < content.len() and (h == 0 or content.get(h - 1) == Ok(' ') or content.get(h - 1) == Ok('\t')) {
					Bytes.trim(content.take_first(h), heading_space)
				} else {
					content
				}
			Ok({ level, content: closed })
		}
	}

	## An ATX heading, its content's inlines rendered between its tags.
	heading_onto : List(U8), { level : U64, content : List(U8), after : U64, budget : MdText.Budget, uploads : MdSafety.Uploads, dialect : MdDialect.Dialect } -> Try(MdText.Block, [Hostile])
	heading_onto = |out, { level, content, after, budget, uploads, dialect }| {
		heading = MdInline.render_onto({
			out: out.concat(
				match dialect {
					Chat => MdHtml.heading_open(level)
					Document(_) => MdHtml.heading_open_with_id(level, [])
				},
			),
			text: content,
			refs: MdDialect.inline_refs(dialect),
			budget,
			uploads,
		})?
		Ok({ out: heading.out.concat(MdHtml.heading_close(level)), budget: heading.budget, after })
	}
}

heading_space : List(U8)
heading_space = [' ', '\t']
