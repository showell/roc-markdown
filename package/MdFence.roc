## **A MARKDOWN FENCE AS chat-markdown's markdown_fence.zig READS IT**: where a
## code fence opens (its character, its length, its indent, its language)
## and where it closes. The renderer's fences (Md) and the code feed's and
## Recent's excerpt's (Feeds, Recent, metal-vmm QUEUE 300) are this one
## grammar. Pure.
import Bytes

MdFence := [].{

	## A fence's opening line: `count` of `char`, after `indent` spaces, and
	## the first word of its info string.
	Open : {
		char : U8,
		count : U64,
		indent : U64,
		lang : List(U8),
	}

	## markdown_fence `parseOpen`: up to three spaces, 3 to 10 of '`' or '~'
	## (a longer run is past the nesting cap, ordinary text), and an info
	## string whose first word is the language; a backtick fence's info
	## string holds no backtick.
	open : List(U8) -> Try(Open, [NotAFence])
	open = |line| {
		indent = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), 4)
		match List.get(line, indent) {
			Err(_) => Err(NotAFence)
			Ok(f) =>
				if indent >= 4 or (f != '`' and f != '~') {
					Err(NotAFence)
				} else {
					count = Bytes.count_while(line, { keep: |c| c == f, at: indent }) - indent
					info = Bytes.trim(List.drop_first(line, indent + count), info_space)
					if count < 3 or count > max_run or (f == '`' and List.contains(info, '`')) {
						Err(NotAFence)
					} else {
						lang = List.take_first(
							info,
							Bytes.count_while(info, { keep: |c| c != ' ' and c != '\t', at: 0 }),
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

	## markdown_fence `isClose`: up to three spaces, at least `count` of
	## `char`, then only whitespace (a close carries no info string).
	is_close : List(U8), { char : U8, count : U64 } -> Bool
	is_close = |line, { char, count }| {
		indent = U64.min(Bytes.count_while(line, { keep: |c| c == ' ', at: 0 }), 4)
		if indent >= 4 {
			Bool.False
		} else {
			n = Bytes.count_while(line, { keep: |c| c == char, at: indent }) - indent
			n >= count and Bytes.trim(List.drop_first(line, indent + n), info_space) == []
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
		while $j < List.len(lines) and !is_close(List.get(lines, $j) ?? [], { char, count }) {
			$j = $j + 1
		}
		$j
	}
}

## markdown_fence `max_nest_levels` (8) plus 2: a level-8 quote-reply opens
## with 10 characters, and a longer run is no fence.
max_run : U64
max_run = 10

info_space : List(U8)
info_space = [
	' ',
	'\t',
	'\r',
]

# markdown_fence's own cases.
expect MdFence.open(Str.to_utf8("~~~~ quote")) == Ok({
	char: '~',
	count: 4,
	indent: 0,
	lang: Str.to_utf8("quote"),
})
expect MdFence.open(Str.to_utf8("```zig")) == Ok({
	char: '`',
	count: 3,
	indent: 0,
	lang: Str.to_utf8("zig"),
})
expect MdFence.open(Str.to_utf8("plain text")) == Err(NotAFence)
expect MdFence.open(Str.to_utf8("~~ short")) == Err(NotAFence)
expect MdFence.open(Str.to_utf8("```a`b")) == Err(NotAFence)
expect MdFence.open(List.repeat('~', 10)) == Ok({
	char: '~',
	count: 10,
	indent: 0,
	lang: [],
})
expect MdFence.open(List.repeat('~', 11)) == Err(NotAFence)
expect MdFence.open(List.repeat('`', 15)) == Err(NotAFence)
expect MdFence.open(Str.to_utf8("   ~~~ a b")) == Ok({
	char: '~',
	count: 3,
	indent: 3,
	lang: Str.to_utf8("a"),
})
expect MdFence.open(Str.to_utf8("    ~~~")) == Err(NotAFence)
expect !MdFence.is_close(Str.to_utf8("~~~"), { char: '~', count: 4 })
expect MdFence.is_close(Str.to_utf8("~~~~"), { char: '~', count: 4 })
expect MdFence.is_close(Str.to_utf8("~~~~~"), { char: '~', count: 4 })
expect !MdFence.is_close(Str.to_utf8("```"), { char: '~', count: 3 })
expect !MdFence.is_close(Str.to_utf8("~~~ quote"), { char: '~', count: 3 })
expect MdFence.close_at(
	[Str.to_utf8("a"), Str.to_utf8("~~~")],
	{
		char: '~',
		count: 3,
		at: 0,
	},
) == 1
expect MdFence.close_at(
	[Str.to_utf8("a")],
	{
		char: '~',
		count: 3,
		at: 0,
	},
) == 1
