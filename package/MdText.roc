## **THE MARKDOWN'S TEXT PRIMITIVES**: the
## work budget the renderer charges, HTML escaping, and the classes of byte
## the dialect's grammar asks about. Pure; every other `Md` module stands
## on it, and it on nothing of theirs.
##
## The renderer is byte-level parsing at the door: it reads a message's
## bytes, so it works on `List(U8)` throughout and slices
## only at ASCII bytes, which leaves UTF-8 text whole.
import Ascii
import Bytes

MdText := [].{

	## The work one render may do: the parser charges
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

	## What a block's renderer made, and where the source after it starts.
	Block : {
		out : List(U8),
		budget : Budget,
		after : U64,
	}

	## A container's content (a list item's, a quote's), handed back to Md's
	## dispatcher to render as blocks one level deeper (MdList, MdQuote).
	## `Tight` is a tight list item's: its paragraphs have no `<p>`.
	Nested : {
		out : List(U8),
		md : List(U8),
		spacing : [Tight, Loose],
		budget : Budget,
	}

	## A member's message's budget: 16 units a byte, and 256 over. The
	## densest linear text costs about 4.5 a byte.
	for_input : List(U8) -> Budget
	for_input = |md| { spent: 0, ceiling: per_byte * md.len() + base }

	## The budget of server-owned text, and of a measurement: never blown.
	unlimited : Budget
	unlimited = { spent: 0, ceiling: U64.highest }

	charge : Budget, U64 -> Budget
	charge = |budget, units| { ..budget, spent: budget.spent + units }

	is_blown : Budget -> Bool
	is_blown = |budget| budget.spent > budget.ceiling

	## `text` onto `out`, its `&`, `<`, `>`, `"` and `'` as entities: THE
	## escape, which every byte of a
	## member's text the renderer writes passes through.
	escape_onto : List(U8), List(U8) -> List(U8)
	escape_onto = |out, text| {
		var $out = out
		for c in text {
			$out = match c {
				'&' => $out.concat(amp)
				'<' => $out.concat(lt)
				'>' => $out.concat(gt)
				'"' => $out.concat(quot)
				'\'' => $out.concat(apos)
				_ => $out.append(c)
			}
		}
		$out
	}

	## `s` from `start` up to `end`, a Zig slice `s[start..end]`.
	cut : List(U8), { start : U64, end : U64 } -> List(U8)
	cut = |s, { start, end }| s.sublist({ start, len: end - start })

	## The byte at `i`, which the caller has checked is there.
	at : List(U8), U64 -> U8
	at = |s, i| match s.get(i) {
		Ok(c) => c
		Err(OutOfBounds) => crash "MdText.at: a read past the end the caller checked"
	}

	## Space, tab, `\n`, `\r` and form feed; not a
	## vertical tab, which `Ascii.is_whitespace` has.
	is_space : U8 -> Bool
	is_space = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == form_feed

	## What `\b` reads as a word.
	is_word_char : U8 -> Bool
	is_word_char = |c| Ascii.is_alphanumeric(c) or c == '_'

	## An HTML attribute's name.
	is_attr_name_char : U8 -> Bool
	is_attr_name_char = |c| Ascii.is_alphanumeric(c) or c == '-' or c == '_' or c == ':'

	## One digit or more, and nothing else.
	is_all_digits : List(U8) -> Bool
	is_all_digits = |s| s != [] and s.all(Ascii.is_digit)

	## `s` is `lower`, a lowercase literal, in any case.
	is_same_ignoring_case : List(U8), List(U8) -> Bool
	is_same_ignoring_case = |s, lower| s.len() == lower.len() and s.map(Ascii.to_lowercase) == lower

	## `s` from `at` begins with `prefix`, in
	## any case.
	is_prefixed_ignoring_case : List(U8), { at : U64, prefix : List(U8) } -> Bool
	is_prefixed_ignoring_case = |s, { at: i, prefix }| {
		n = prefix.len()
		if i + n > s.len() {
			Bool.False
		} else {
			cut(s, { start: i, end: i + n }).map(Ascii.to_lowercase) == prefix.map(Ascii.to_lowercase)
		}
	}

	## The first `byte` at `at` or after, or the end: `indexOfScalarPos`
	## orelse `len`.
	find_or_end : List(U8), { byte : U8, at : U64 } -> U64
	find_or_end = |s, wanted| Bytes.find_byte(s, wanted) ?? List.len(s)

	## Spaces, tabs and `\r` off both ends.
	trim_line : List(U8) -> List(U8)
	trim_line = |line| Bytes.trim(line, line_space)

	## CommonMark's backslash escapes taken out of `text`: a backslash before
	## ASCII punctuation is dropped and the punctuation kept; any other is a
	## backslash. For text no inline pass reads (a fence's info string).
	unescaped : List(U8) -> List(U8)
	unescaped = |text| {
		len = text.len()
		var $out = []
		var $i = 0
		while $i < len {
			c = at(text, $i)
			if c == '\\' and $i + 1 < len and Ascii.is_punctuation(at(text, $i + 1)) {
				$out = $out.append(at(text, $i + 1))
				$i = $i + 2
			} else {
				$out = $out.append(c)
				$i = $i + 1
			}
		}
		$out
	}

	## Nothing but spaces, tabs and `\r`.
	is_blank : List(U8) -> Bool
	is_blank = |line| line.all(|c| c == ' ' or c == '\t' or c == '\r')

	## The `\n` ending the line at `pos`, or the end.
	line_end : List(U8), U64 -> U64
	line_end = |md, pos| find_or_end(md, { byte: '\n', at: pos })

	## The start of the line after the one ending at `eol`.
	next_line : List(U8), U64 -> U64
	next_line = |md, eol| if (eol < md.len()) eol + 1 else md.len()
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
amp = "&amp;".to_utf8()

lt : List(U8)
lt = "&lt;".to_utf8()

gt : List(U8)
gt = "&gt;".to_utf8()

quot : List(U8)
quot = "&quot;".to_utf8()

## `'` as roc-chat's pages have always written it: so an escaped value is
## safe in a single-quoted attribute too.
apos : List(U8)
apos = "&#39;".to_utf8()

expect MdText.escape_onto([], "a<b>&\"c'".to_utf8()) == "a&lt;b&gt;&amp;&quot;c&#39;".to_utf8()
expect MdText.for_input("abc".to_utf8()).ceiling == 304
expect MdText.is_blown(MdText.charge({ spent: 0, ceiling: 3 }, 4))
expect !MdText.is_blown(MdText.charge({ spent: 0, ceiling: 3 }, 3))
expect MdText.is_prefixed_ignoring_case(
	"xHTTP://".to_utf8(),
	{ at: 1, prefix: "http://".to_utf8() },
)
expect !MdText.is_prefixed_ignoring_case(
	"http:/".to_utf8(),
	{ at: 0, prefix: "http://".to_utf8() },
)
expect MdText.is_same_ignoring_case("ViDeO".to_utf8(), "video".to_utf8())
expect MdText.is_blank(" \t\r".to_utf8())
expect !MdText.is_blank(" \u(a0)".to_utf8())
