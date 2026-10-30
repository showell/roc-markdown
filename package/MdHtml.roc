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
	p_open = "<p>".to_utf8()

	p_close : List(U8)
	p_close = "</p>\n".to_utf8()

	## A hard wrap's line break, in the hard-wrap mode's paragraphs.
	br : List(U8)
	br = "<br>\n".to_utf8()

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
			"<pre><code>".to_utf8()
		} else {
			List.concat(
				MdText.escape_onto(Str.to_utf8("<pre><code class=\"language-"), lang),
				['"', '>'],
			)
		}

	code_block_close : List(U8)
	code_block_close = "</code></pre>\n".to_utf8()

	## The chat's quote-reply (a `quote` fence, MdChat): preformatted, but no
	## code.
	chat_quote_open : List(U8)
	chat_quote_open = "<pre class=\"chat-quote\">".to_utf8()

	chat_quote_close : List(U8)
	chat_quote_close = "</pre>\n".to_utf8()

	ul_open : List(U8)
	ul_open = "<ul>\n".to_utf8()

	ul_close : List(U8)
	ul_close = "</ul>\n".to_utf8()

	## An ordered list's opening, its `start` when that is not 1.
	ol_open : U64 -> List(U8)
	ol_open = |start| if start == 1 "<ol>\n".to_utf8() else "<ol start=\"${start.to_str()}\">\n".to_utf8()

	ol_close : List(U8)
	ol_close = "</ol>\n".to_utf8()

	li_open : List(U8)
	li_open = "<li>".to_utf8()

	li_close : List(U8)
	li_close = "</li>\n".to_utf8()

	blockquote_open : List(U8)
	blockquote_open = "<blockquote>\n".to_utf8()

	blockquote_close : List(U8)
	blockquote_close = "</blockquote>\n".to_utf8()

	## A table's opening, up to its header row.
	table_open : List(U8)
	table_open = "<table>\n<thead>\n".to_utf8()

	thead_close : List(U8)
	thead_close = "</thead>\n".to_utf8()

	tbody_open : List(U8)
	tbody_open = "<tbody>\n".to_utf8()

	tbody_close : List(U8)
	tbody_close = "</tbody>\n".to_utf8()

	table_close : List(U8)
	table_close = "</table>\n".to_utf8()

	tr_open : List(U8)
	tr_open = "<tr>\n".to_utf8()

	tr_close : List(U8)
	tr_close = "</tr>\n".to_utf8()

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
		name.to_utf8().concat(attr.to_utf8()).append('>')
	}

	cell_close : [Th, Td] -> List(U8)
	cell_close = |tag| (if tag == Th "</th>\n" else "</td>\n").to_utf8()

	## What a hostile message renders as: a paragraph the client is free to
	## style as `.md-malformed`.
	malformed : List(U8)
	malformed = "<p class=\"md-malformed\">⚠️ malformed markdown — not rendered</p>\n".to_utf8()

	# ── inline ──

	code_open : List(U8)
	code_open = "<code>".to_utf8()

	code_close : List(U8)
	code_close = "</code>".to_utf8()

	em_open : List(U8)
	em_open = "<em>".to_utf8()

	em_close : List(U8)
	em_close = "</em>".to_utf8()

	strong_open : List(U8)
	strong_open = "<strong>".to_utf8()

	strong_close : List(U8)
	strong_close = "</strong>".to_utf8()

	## GFM's strikethrough, `~~text~~` (MdEmphasis).
	del_open : List(U8)
	del_open = "<del>".to_utf8()

	del_close : List(U8)
	del_close = "</del>".to_utf8()

	## A link's opening tag: its href escaped (an empty one where MdSafety
	## dropped it), and a new tab, without the opener, when `NewTab`.
	link_open : { href : List(U8), tab : [SameTab, NewTab] } -> List(U8)
	link_open = |{ href, tab }| List.join([
		MdText.escape_onto(Str.to_utf8("<a href=\""), href),
		['"'],
		if tab == NewTab " target=\"_blank\" rel=\"noopener\"".to_utf8() else [],
		['>'],
	])

	link_close : List(U8)
	link_close = "</a>".to_utf8()

	## The chat's message reference (MdChat): a link to the message's anchor,
	## `#msg-<slug>`, its label the reference as written. The slug grammar has
	## no byte HTML gives a meaning, so both are written as they are.
	msg_ref : { slug : List(U8), label : List(U8) } -> List(U8)
	msg_ref = |{ slug, label }| [
		"<a href=\"#msg-".to_utf8(),
		slug,
		"\" class=\"msg-ref\">".to_utf8(),
		label,
		link_close,
	].join()

	# ── media ──

	## One attribute of a rebuilt media tag: ` name`, or ` name="value"`,
	## the value escaped.
	Attr : {
		name : List(U8),
		value : [Bare, Is(List(U8))],
	}

	## A member's `<img>`, rebuilt from the attributes MdSafety let through.
	img : List(Attr) -> List(U8)
	img = |attrs| attrs_onto("<img".to_utf8(), attrs).append('>')

	## The text of html this renderer wrote, its markup gone: every tag
	## dropped and the escapes MdText writes read back, so the text can be
	## escaped once more as an attribute's value. An image's alt is its
	## label's inline content so read (CommonMark's "plain string content").
	## Each `<` here opens a tag (a member's `<` is `&lt;`), and a tag ends
	## at its first `>` (one inside a value is `&gt;`).
	plain_text : List(U8) -> List(U8)
	plain_text = |html| {
		len = html.len()
		var $out = []
		var $i = 0
		while $i < len {
			c = MdText.at(html, $i)
			if c == '<' {
				$i = MdText.find_or_end(html, { byte: '>', at: $i }) + 1
			} else if c == '&' {
				match List.find_first(entities, |e| MdText.is_prefixed_ignoring_case(html, { at: $i, prefix: e.0 })) {
					Ok((written, byte)) => {
						$out = $out.append(byte)
						$i = $i + written.len()
					}
					Err(NotFound) => {
						$out = $out.append(c)
						$i = $i + 1
					}
				}
			} else {
				$out = $out.append(c)
				$i = $i + 1
			}
		}
		$out
	}

	## A member's `<video>`, rebuilt as a player with no fallback content.
	video : List(Attr) -> List(U8)
	video = |attrs| attrs_onto("<video".to_utf8(), attrs).concat("></video>".to_utf8())
}

## The escapes MdText writes, and the byte each stands for.
entities : List((List(U8), U8))
entities = [
	("&amp;".to_utf8(), '&'),
	("&lt;".to_utf8(), '<'),
	("&gt;".to_utf8(), '>'),
	("&quot;".to_utf8(), '"'),
	("&#39;".to_utf8(), '\''),
]

heading_digit : U64 -> U8
heading_digit = |level| '0' + level.to_u8_wrap()

attrs_onto : List(U8), List(MdHtml.Attr) -> List(U8)
attrs_onto = |out, attrs| {
	var $out = out
	for { name, value } in attrs {
		named = $out.append(' ').concat(name)
		$out = match value {
			Bare => named
			Is(v) => List.append(MdText.escape_onto(List.concat(named, ['=', '"']), v), '"')
		}
	}
	$out
}

expect MdHtml.heading_open(3) == "<h3>".to_utf8()
expect MdHtml.plain_text("foo <em>bar</em> &amp; <code>a&lt;b</code> &quot;q&quot;".to_utf8()) == "foo bar & a<b \"q\"".to_utf8()
expect MdHtml.plain_text("<a href=\"/u?a&amp;b\" target=\"_blank\">x</a>".to_utf8()) == "x".to_utf8()
expect MdHtml.ol_open(4) == "<ol start=\"4\">\n".to_utf8()
expect MdHtml.link_open({ href: "/a?b&c".to_utf8(), tab: SameTab }) == "<a href=\"/a?b&amp;c\">".to_utf8()
expect MdHtml.video([{ name: "controls".to_utf8(), value: Bare }, { name: "src".to_utf8(), value: Is("/v\".mp4".to_utf8()) }]) == "<video controls src=\"/v&quot;.mp4\"></video>".to_utf8()
