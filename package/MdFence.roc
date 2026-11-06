## **A MARKDOWN FENCE**: where a code fence opens (its character, its
## length, its indent, its language) and where it closes. Exposed, so a host
## that reads fences outside a render (a code feed, an excerpt) reads the
## very grammar the renderer does. Pure.
import Bytes
import MdChat
import MdDialect
import MdHtml
import MdText

MdFence := [].{

	## A fence's opening line: `count` of `char`, after `indent` spaces, and
	## the first word of its info string.
	Open : {
		char : U8,
		count : U64,
		indent : U64,
		lang : List(U8),
	}

	## Up to three spaces, 3 to 10 of '`' or '~'
	## (a longer run is past the quote-reply's nesting cap, MdChat's, and
	## ordinary text), and an info
	## string whose first word is the language; a backtick fence's info
	## string holds no backtick.
	open : List(U8) -> Try(Open, [NotAFence])
	open = |line| {
		indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
		match line.get(indent) {
			Err(_) => Err(NotAFence)
			Ok(f) =>
				if indent >= 4 or (f != '`' and f != '~') {
					Err(NotAFence)
				} else {
					count = Bytes.count_while(line, { keep: |c| c == f, at: indent }) - indent
					info = Bytes.trim(line.drop_first(indent + count), info_space)
					if count < 3 or count > MdChat.max_fence_run or (f == '`' and info.contains('`')) {
						Err(NotAFence)
					} else {
						# The language's backslash escapes are CommonMark's (`foo\+bar`).
						lang = MdText.unescaped(
							info.take_first(Bytes.count_while(info, { keep: |c| c != ' ' and c != '\t', at: 0 })),
						)
						Ok({
							char: f,
							count,
							indent,
							lang,
						})
					}
				}
		}
	}

	## A fence's opening at the line of `md` at `line_start`, and where its body
	## starts: the block dispatcher's (Md) question.
	open_at : List(U8), U64 -> Try({ open : Open, body_start : U64 }, [NotAFence])
	open_at = |md, line_start| {
		eol = MdText.line_end(md, line_start)
		fence = MdFence.open(MdText.cut(md, { start: line_start, end: eol }))?
		Ok({ open: fence, body_start: MdText.next_line(md, eol) })
	}

	## The info string after the language, on the opening line `line`.
	args : List(U8), Open -> List(U8)
	args = |line, open_line| {
		info = Bytes.trim(line.drop_first(open_line.indent + open_line.count), info_space)
		Bytes.trim(info.drop_first(Bytes.count_while(info, { keep: |c| c != ' ' and c != '\t', at: 0 })), info_space)
	}

	## The code block, up to its closing fence or the
	## end (an unclosed fence runs to the end). Its body is charged whole, its
	## close-scan and escape being linear in it; no check follows here.
	fence_onto : List(U8),
	{
		md : List(U8),
		open : { open : MdFence.Open, body_start : U64 },
		line : List(U8),
		budget : MdText.Budget,
		dialect : MdDialect.Dialect,
	} -> MdText.Block
	fence_onto = |
		out,
		{
			md,
			open: { open: fence, body_start },
			line,
			budget,
			dialect,
		},
	| {
		len = md.len()
		var $content_end = len
		var $after = len
		var $p = body_start
		while $p < len {
			eol = MdText.line_end(md, $p)
			if MdFence.is_close(
				MdText.cut(md, { start: $p, end: eol }),
				{ char: fence.char, count: fence.count },
			) {
				$content_end = $p
				$after = MdText.next_line(md, eol)
				break
			} else {
				$p = MdText.next_line(md, eol)
			}
		}
		content = MdText.cut(md, { start: body_start, end: $content_end })
		body = dedented({ content, indent: fence.indent })
		code = || MdText.escape_onto(MdHtml.code_block_open(fence.lang), body).concat(MdHtml.code_block_close)
		block = match dialect {
			Chat if MdChat.is_quote_fence(fence.lang) => MdText.escape_onto(MdHtml.chat_quote_open, body).concat(MdHtml.chat_quote_close)
			Chat => code()
			Document(options) =>
				match (options.fence)({ tag: fence.lang, args: MdFence.args(line, fence), body }) {
					Html(html) => html
					Pass => code()
				}
		}
		{
			out: out.concat(block),
			budget: MdText.charge(budget, content.len()),
			after: $after,
		}
	}

	## Up to three spaces, at least `count` of
	## `char`, then only whitespace (a close carries no info string).
	is_close : List(U8), { char : U8, count : U64 } -> Bool
	is_close = |line, { char, count }| {
		indent = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(4)
		if indent >= 4 {
			Bool.False
		} else {
			n = Bytes.count_while(line, { keep: |c| c == char, at: indent }) - indent
			n >= count and Bytes.trim(line.drop_first(indent + n), info_space) == []
		}
	}

	## The index of the line in `lines`, from `at` on, that closes a fence of
	## `count` `char`s, or the count of lines when none does: an unclosed
	## fence runs to the end.
	close_at : List(List(U8)),
	{
		char : U8,
		count : U64,
		at : U64,
	} -> U64
	close_at = |
		lines,
		{
			char,
			count,
			at,
		},
	| {
		var $j = at
		while $j < lines.len() and !is_close(lines.get($j) ?? [], { char, count }) {
			$j = $j + 1
		}
		$j
	}
}

## Each line ended with a newline, less up to the fence's own indent of
## spaces.
dedented : { content : List(U8), indent : U64 } -> List(U8)
dedented = |{ content, indent }| {
	len = content.len()
	var $out = []
	var $i = 0
	while $i < len {
		eol = MdText.line_end(content, $i)
		line = MdText.cut(content, { start: $i, end: eol })
		strip = Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }).min(indent)
		$out = $out.concat(line.drop_first(strip)).append('\n')
		$i = MdText.next_line(content, eol)
	}
	$out
}

info_space : List(U8)
info_space = [
	' ',
	'\t',
	'\r',
]

# Where a fence opens and closes: its run's length and cap, its indent, its
# language, and a backtick fence's info string.
expect MdFence.open("~~~~ quote".to_utf8()) == Ok({
	char: '~',
	count: 4,
	indent: 0,
	lang: "quote".to_utf8(),
})
expect MdFence.open("```zig".to_utf8()) == Ok({
	char: '`',
	count: 3,
	indent: 0,
	lang: "zig".to_utf8(),
})
expect MdFence.args("  ```widget  big sky ".to_utf8(), { char: '`', count: 3, indent: 2, lang: "widget".to_utf8() }) == "big sky".to_utf8()
expect MdFence.args("```widget".to_utf8(), { char: '`', count: 3, indent: 0, lang: "widget".to_utf8() }) == []
expect MdFence.open("plain text".to_utf8()) == Err(NotAFence)
expect MdFence.open("~~ short".to_utf8()) == Err(NotAFence)
expect MdFence.open("```a`b".to_utf8()) == Err(NotAFence)
expect MdFence.open(List.repeat('~', 10)) == Ok({
	char: '~',
	count: 10,
	indent: 0,
	lang: [],
})
expect MdFence.open(List.repeat('~', 11)) == Err(NotAFence)
expect MdFence.open(List.repeat('`', 15)) == Err(NotAFence)
expect MdFence.open("   ~~~ a b".to_utf8()) == Ok({
	char: '~',
	count: 3,
	indent: 3,
	lang: "a".to_utf8(),
})
expect MdFence.open("    ~~~".to_utf8()) == Err(NotAFence)
expect MdFence.open("``` foo\\+bar\\x".to_utf8()).map_ok(|o| o.lang) == Ok("foo+bar\\x".to_utf8())
expect !MdFence.is_close("~~~".to_utf8(), { char: '~', count: 4 })
expect MdFence.is_close("~~~~".to_utf8(), { char: '~', count: 4 })
expect MdFence.is_close("~~~~~".to_utf8(), { char: '~', count: 4 })
expect !MdFence.is_close("```".to_utf8(), { char: '~', count: 3 })
expect !MdFence.is_close("~~~ quote".to_utf8(), { char: '~', count: 3 })
expect MdFence.close_at(
	["a".to_utf8(), "~~~".to_utf8()],
	{
		char: '~',
		count: 3,
		at: 0,
	},
) == 1
expect MdFence.close_at(
	["a".to_utf8()],
	{
		char: '~',
		count: 3,
		at: 0,
	},
) == 1
