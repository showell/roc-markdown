## **THE MARKDOWN'S TEXT PRIMITIVES** (chat-markdown markdown_text.zig): the
## work budget the renderer charges, HTML escaping, and the classes of byte
## the dialect's grammar asks about. Pure; every other `Md` module stands
## on it, and it on nothing of theirs.
##
## The renderer is byte-level parsing at the door: it reads a message's
## bytes as the Zig does, so it works on `List(U8)` throughout and slices
## only at ASCII bytes, which leaves UTF-8 text whole.
import Ascii
import Bytes

MdText := [].{

	## The work one render may do (markdown_text `Budget`): the parser charges
	## a unit per scan step, and a render whose `spent` passes `ceiling` at a
	## check is hostile. The parser is linear by its cursors, so ordinary
	## text stays far under; only a re-parse goes past.
	Budget : {
		spent : U64,
		ceiling : U64,
	}

	## What a render has made so far, and what it has spent.
	Rendered : {
		out : List(U8),
		budget : Budget,
	}

	## A member's message's budget: 16 units a byte, and 256 over. The
	## densest linear text costs about 4.5 a byte.
	for_input : List(U8) -> Budget
	for_input = |md| { spent: 0, ceiling: per_byte * List.len(md) + base }

	## The budget of server-owned text, and of a measurement: never blown.
	unlimited : Budget
	unlimited = { spent: 0, ceiling: U64.highest }

	charge : Budget, U64 -> Budget
	charge = |budget, units| { ..budget, spent: budget.spent + units }

	is_blown : Budget -> Bool
	is_blown = |budget| budget.spent > budget.ceiling

	## `text` onto `out`, its `&`, `<`, `>` and `"` as entities
	## (markdown_text `escapeInto`): THE escape, which every byte of a
	## member's text the renderer writes passes through.
	escape_onto : List(U8), List(U8) -> List(U8)
	escape_onto = |out, text| {
		var $out = out
		for c in text {
			$out = match c {
				'&' => List.concat($out, amp)
				'<' => List.concat($out, lt)
				'>' => List.concat($out, gt)
				'"' => List.concat($out, quot)
				_ => List.append($out, c)
			}
		}
		$out
	}

	## `s` from `start` up to `end`, a Zig slice `s[start..end]`.
	cut : List(U8), { start : U64, end : U64 } -> List(U8)
	cut = |s, { start, end }| List.sublist(s, { start, len: end - start })

	## The byte at `i`, which the caller has checked is there.
	at : List(U8), U64 -> U8
	at = |s, i| match List.get(s, i) {
		Ok(c) => c
		Err(OutOfBounds) => crash "MdText.at: a read past the end the caller checked"
	}

	## markdown_text `isSpace`: space, tab, `\n`, `\r` and form feed; not a
	## vertical tab, which `Ascii.is_whitespace` has.
	is_space : U8 -> Bool
	is_space = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == form_feed

	## markdown_text `isWordChar`: what `\b` reads as a word.
	is_word_char : U8 -> Bool
	is_word_char = |c| Ascii.is_alphanumeric(c) or c == '_'

	## markdown_text `isSlugChar`: a `MSG_` reference's slug.
	is_slug_char : U8 -> Bool
	is_slug_char = |c| Ascii.is_alphanumeric(c) or c == '-'

	## markdown_text `isAttrNameChar`: an HTML attribute's name.
	is_attr_name_char : U8 -> Bool
	is_attr_name_char = |c| Ascii.is_alphanumeric(c) or c == '-' or c == '_' or c == ':'

	## markdown_text `allDigits`: one digit or more, and nothing else.
	is_all_digits : List(U8) -> Bool
	is_all_digits = |s| s != [] and List.all(s, Ascii.is_digit)

	## markdown_text `eqlCI`: `s` is `lower`, a lowercase literal, in any case.
	is_same_ignoring_case : List(U8), List(U8) -> Bool
	is_same_ignoring_case = |s, lower| List.len(s) == List.len(lower) and List.map(
		s,
		Ascii.to_lowercase,
	) == lower

	## markdown_text `startsWithCI`: `s` from `at` begins with `prefix`, in
	## any case.
	is_prefixed_ignoring_case : List(U8), { at : U64, prefix : List(U8) } -> Bool
	is_prefixed_ignoring_case = |s, { at: i, prefix }| {
		n = List.len(prefix)
		if i + n > List.len(s) {
			Bool.False
		} else {
			List.map(
				cut(s, { start: i, end: i + n }),
				Ascii.to_lowercase,
			) == List.map(prefix, Ascii.to_lowercase)
		}
	}

	## The first `byte` at `at` or after, or the end: `indexOfScalarPos`
	## orelse `len`.
	find_or_end : List(U8), { byte : U8, at : U64 } -> U64
	find_or_end = |s, wanted| Bytes.find_byte(s, wanted) ?? List.len(s)

	## markdown.zig's `trimLine`: spaces, tabs and `\r` off both ends.
	trim_line : List(U8) -> List(U8)
	trim_line = |line| Bytes.trim(line, line_space)

	## markdown.zig's `isBlank`: nothing but spaces, tabs and `\r`.
	is_blank : List(U8) -> Bool
	is_blank = |line| List.all(line, |c| c == ' ' or c == '\t' or c == '\r')

	## markdown.zig's `lineEnd`: the `\n` ending the line at `pos`, or the end.
	line_end : List(U8), U64 -> U64
	line_end = |md, pos| find_or_end(md, { byte: '\n', at: pos })

	## The start of the line after the one ending at `eol`.
	next_line : List(U8), U64 -> U64
	next_line = |md, eol| if eol < List.len(md) eol + 1 else List.len(md)
}

per_byte : U64
per_byte = 16

base : U64
base = 256

form_feed : U8
form_feed = 12

line_space : List(U8)
line_space = [
	' ',
	'\t',
	'\r',
]

amp : List(U8)
amp = Str.to_utf8("&amp;")

lt : List(U8)
lt = Str.to_utf8("&lt;")

gt : List(U8)
gt = Str.to_utf8("&gt;")

quot : List(U8)
quot = Str.to_utf8("&quot;")

expect MdText.escape_onto([], Str.to_utf8("a<b>&\"c'")) == Str.to_utf8("a&lt;b&gt;&amp;&quot;c'")
expect MdText.for_input(Str.to_utf8("abc")).ceiling == 304
expect MdText.is_blown(MdText.charge({ spent: 0, ceiling: 3 }, 4))
expect !MdText.is_blown(MdText.charge({ spent: 0, ceiling: 3 }, 3))
expect MdText.is_prefixed_ignoring_case(
	Str.to_utf8("xHTTP://"),
	{ at: 1, prefix: Str.to_utf8("http://") },
)
expect !MdText.is_prefixed_ignoring_case(
	Str.to_utf8("http:/"),
	{ at: 0, prefix: Str.to_utf8("http://") },
)
expect MdText.is_same_ignoring_case(Str.to_utf8("ViDeO"), Str.to_utf8("video"))
expect MdText.is_blank(Str.to_utf8(" \t\r"))
expect !MdText.is_blank(Str.to_utf8(" \u(a0)"))
