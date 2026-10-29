## **EVERY TAG AND ATTRIBUTE THE RENDERER WRITES**, in one place: a fork
## that wants other tags or classes (a table wrapper that scrolls, a class on
## a code block, other link attributes) edits this module alone. Each block
## and inline module asks here for its markup and writes only the member's
## text, escaped by MdText, between.
##
## What stays elsewhere: which attributes a member's `<img>` or `<video>`
## keeps, and what a video player is given, is a safety rule (MdSafety); the
## whitespace between blocks is the dispatcher's (Md). Pure.
import MdText
import MdTable

MdHtml := [].{

	# ── blocks ──

	p_open : List(U8)
	p_open = Str.to_utf8("<p>")

	p_close : List(U8)
	p_close = Str.to_utf8("</p>\n")

	## A hard wrap's line break, in the hard-wrap mode's paragraphs.
	br : List(U8)
	br = Str.to_utf8("<br>\n")

	## `<h1>` to `<h6>`, by the heading's level.
	heading_open : U64 -> List(U8)
	heading_open = |level| ['<', 'h', heading_digit(level), '>']

	heading_close : U64 -> List(U8)
	heading_close = |level| ['<', '/', 'h', heading_digit(level), '>', '\n']

	## A code block's opening, its language (escaped) as a `language-` class
	## when it has one.
	code_block_open : List(U8) -> List(U8)
	code_block_open = |lang|
		if lang == [] {
			Str.to_utf8("<pre><code>")
		} else {
			List.concat(
				MdText.escape_onto(Str.to_utf8("<pre><code class=\"language-"), lang),
				['"', '>'],
			)
		}

	code_block_close : List(U8)
	code_block_close = Str.to_utf8("</code></pre>\n")

	## The chat's quote-reply (a `quote` fence, MdChat): preformatted, but no
	## code.
	chat_quote_open : List(U8)
	chat_quote_open = Str.to_utf8("<pre class=\"chat-quote\">")

	chat_quote_close : List(U8)
	chat_quote_close = Str.to_utf8("</pre>\n")

	ul_open : List(U8)
	ul_open = Str.to_utf8("<ul>\n")

	ul_close : List(U8)
	ul_close = Str.to_utf8("</ul>\n")

	## An ordered list's opening, its `start` when that is not 1.
	ol_open : U64 -> List(U8)
	ol_open = |start| if start == 1 Str.to_utf8("<ol>\n") else Str.to_utf8("<ol start=\"${start.to_str()}\">\n")

	ol_close : List(U8)
	ol_close = Str.to_utf8("</ol>\n")

	li_open : List(U8)
	li_open = Str.to_utf8("<li>")

	li_close : List(U8)
	li_close = Str.to_utf8("</li>\n")

	blockquote_open : List(U8)
	blockquote_open = Str.to_utf8("<blockquote>\n")

	blockquote_close : List(U8)
	blockquote_close = Str.to_utf8("</blockquote>\n")

	## A table's opening, up to its header row.
	table_open : List(U8)
	table_open = Str.to_utf8("<table>\n<thead>\n")

	thead_close : List(U8)
	thead_close = Str.to_utf8("</thead>\n")

	tbody_open : List(U8)
	tbody_open = Str.to_utf8("<tbody>\n")

	tbody_close : List(U8)
	tbody_close = Str.to_utf8("</tbody>\n")

	table_close : List(U8)
	table_close = Str.to_utf8("</table>\n")

	tr_open : List(U8)
	tr_open = Str.to_utf8("<tr>\n")

	tr_close : List(U8)
	tr_close = Str.to_utf8("</tr>\n")

	## `<th>` or `<td>`, with GFM's `align` when the column has one.
	cell_open : [Th, Td], MdTable.Align -> List(U8)
	cell_open = |tag, align| {
		name = if tag == Th "<th" else "<td"
		attr = match align {
			Plain => ""
			Left => " align=\"left\""
			Center => " align=\"center\""
			Right => " align=\"right\""
		}
		List.append(List.concat(Str.to_utf8(name), Str.to_utf8(attr)), '>')
	}

	cell_close : [Th, Td] -> List(U8)
	cell_close = |tag| Str.to_utf8(if tag == Th "</th>\n" else "</td>\n")

	## What a hostile message renders as: a paragraph the client is free to
	## style as `.md-malformed`.
	malformed : List(U8)
	malformed = Str.to_utf8("<p class=\"md-malformed\">⚠️ malformed markdown — not rendered</p>\n")

	# ── inline ──

	code_open : List(U8)
	code_open = Str.to_utf8("<code>")

	code_close : List(U8)
	code_close = Str.to_utf8("</code>")

	em_open : List(U8)
	em_open = Str.to_utf8("<em>")

	em_close : List(U8)
	em_close = Str.to_utf8("</em>")

	strong_open : List(U8)
	strong_open = Str.to_utf8("<strong>")

	strong_close : List(U8)
	strong_close = Str.to_utf8("</strong>")

	## GFM's strikethrough, `~~text~~` (MdEmphasis).
	del_open : List(U8)
	del_open = Str.to_utf8("<del>")

	del_close : List(U8)
	del_close = Str.to_utf8("</del>")

	## A link's opening tag: its href escaped (an empty one where MdSafety
	## dropped it), and a new tab, without the opener, when `NewTab`.
	link_open : { href : List(U8), tab : [SameTab, NewTab] } -> List(U8)
	link_open = |{ href, tab }| List.join([
		MdText.escape_onto(Str.to_utf8("<a href=\""), href),
		['"'],
		if tab == NewTab Str.to_utf8(" target=\"_blank\" rel=\"noopener\"") else [],
		['>'],
	])

	link_close : List(U8)
	link_close = Str.to_utf8("</a>")

	## The chat's message reference (MdChat): a link to the message's anchor,
	## `#msg-<slug>`, its label the reference as written. The slug grammar has
	## no byte HTML gives a meaning, so both are written as they are.
	msg_ref : { slug : List(U8), label : List(U8) } -> List(U8)
	msg_ref = |{ slug, label }| List.join([
		Str.to_utf8("<a href=\"#msg-"),
		slug,
		Str.to_utf8("\" class=\"msg-ref\">"),
		label,
		link_close,
	])

	# ── media ──

	## One attribute of a rebuilt media tag: ` name`, or ` name="value"`,
	## the value escaped.
	Attr : {
		name : List(U8),
		value : [Bare, Is(List(U8))],
	}

	## A member's `<img>`, rebuilt from the attributes MdSafety let through.
	img : List(Attr) -> List(U8)
	img = |attrs| List.append(attrs_onto(Str.to_utf8("<img"), attrs), '>')

	## The text of html this renderer wrote, its markup gone: every tag
	## dropped and the escapes MdText writes read back, so the text can be
	## escaped once more as an attribute's value. An image's alt is its
	## label's inline content so read (CommonMark's "plain string content").
	## Each `<` here opens a tag (a member's `<` is `&lt;`), and a tag ends
	## at its first `>` (one inside a value is `&gt;`).
	plain_text : List(U8) -> List(U8)
	plain_text = |html| {
		len = List.len(html)
		var $out = []
		var $i = 0
		while $i < len {
			c = MdText.at(html, $i)
			if c == '<' {
				$i = MdText.find_or_end(html, { byte: '>', at: $i }) + 1
			} else if c == '&' {
				match List.find_first(entities, |e| MdText.is_prefixed_ignoring_case(html, { at: $i, prefix: e.0 })) {
					Ok((written, byte)) => {
						$out = List.append($out, byte)
						$i = $i + List.len(written)
					}
					Err(NotFound) => {
						$out = List.append($out, c)
						$i = $i + 1
					}
				}
			} else {
				$out = List.append($out, c)
				$i = $i + 1
			}
		}
		$out
	}

	## A member's `<video>`, rebuilt as a player with no fallback content.
	video : List(Attr) -> List(U8)
	video = |attrs| List.concat(attrs_onto(Str.to_utf8("<video"), attrs), Str.to_utf8("></video>"))
}

## The escapes MdText writes, and the byte each stands for.
entities : List((List(U8), U8))
entities = [
	(Str.to_utf8("&amp;"), '&'),
	(Str.to_utf8("&lt;"), '<'),
	(Str.to_utf8("&gt;"), '>'),
	(Str.to_utf8("&quot;"), '"'),
]

heading_digit : U64 -> U8
heading_digit = |level| '0' + level.to_u8_wrap()

attrs_onto : List(U8), List(MdHtml.Attr) -> List(U8)
attrs_onto = |out, attrs| {
	var $out = out
	for { name, value } in attrs {
		named = List.concat(List.append($out, ' '), name)
		$out = match value {
			Bare => named
			Is(v) => List.append(MdText.escape_onto(List.concat(named, ['=', '"']), v), '"')
		}
	}
	$out
}

expect MdHtml.heading_open(3) == Str.to_utf8("<h3>")
expect MdHtml.plain_text(Str.to_utf8("foo <em>bar</em> &amp; <code>a&lt;b</code> &quot;q&quot;")) == Str.to_utf8("foo bar & a<b \"q\"")
expect MdHtml.plain_text(Str.to_utf8("<a href=\"/u?a&amp;b\" target=\"_blank\">x</a>")) == Str.to_utf8("x")
expect MdHtml.ol_open(4) == Str.to_utf8("<ol start=\"4\">\n")
expect MdHtml.link_open({ href: Str.to_utf8("/a?b&c"), tab: SameTab }) == Str.to_utf8("<a href=\"/a?b&amp;c\">")
expect MdHtml.video([{ name: Str.to_utf8("controls"), value: Bare }, { name: Str.to_utf8("src"), value: Is(Str.to_utf8("/v\".mp4")) }]) == Str.to_utf8("<video controls src=\"/v&quot;.mp4\"></video>")
