## Which syntax a render reads: a chat's, or a document's with its options.
## Every question only a document asks goes through here, and a chat's answer is
## no, which keeps every chat answer as it is. Pure.
import MdDocument
import MdIndent
import MdInline
import MdLinks

MdDialect := [].{

	Dialect : [Chat, Document(MdDocument.PageOptions)]

	## How the inline pass reads a dialect's text.
	inline_refs : Dialect -> MdInline.Refs
	inline_refs = |dialect| match dialect {
		Chat => Linked
		Document(options) => Document(options.images)
	}

	## How a dialect counts a line's indent.
	indent_reading : Dialect -> MdIndent.Reading
	indent_reading = |dialect| match dialect {
		Chat => Spaces
		Document(_) => TabStops
	}

	## The line is a rule. A chat has none.
	is_rule : Dialect, List(U8) -> Bool
	is_rule = |dialect, line| match dialect {
		Chat => Bool.False
		Document(_) => MdDocument.is_rule(line)
	}

	## The line opens or continues indented code. A chat has none.
	is_code : Dialect, List(U8) -> Bool
	is_code = |dialect, line| match dialect {
		Chat => Bool.False
		Document(_) => MdDocument.is_indented_code(line)
	}

	## The line is one `<http://…>`, which a chat takes for an HTML tag.
	is_angle_url_line : Dialect, List(U8) -> Bool
	is_angle_url_line = |dialect, line| match dialect {
		Chat => Bool.False
		Document(_) => MdLinks.is_angle_url_line(line)
	}
}
