## **THE INLINE PASS**: one line of inline content to HTML. The line is cut into pieces (text to escape; html made here, for a
## code span, a same-origin `<img>` or `<video>` (MdMedia), a `[t](u)` link,
## a same-origin `![alt](src)` image or an autolink (MdLinks), or the chat's `MSG_` reference (MdChat); and
## `*`/`_`/`~` runs), the
## runs are matched into `<em>`, `<strong>` and `<del>` (MdEmphasis), and
## the pieces are written out. Pure.
##
## **A BACKSLASH BEFORE ASCII PUNCTUATION MAKES IT TEXT** (CommonMark's
## backslash escapes): the backslash goes, and the character after it is a
## piece of text, so it opens no emphasis, link, code span or tag. Before
## anything else a backslash is itself. A code span's content is read raw,
## so a backslash inside one stays (the span is scanned from its backtick,
## never through this pass); so is a fence's (Md).
##
## **LINEAR BY ITS CURSORS, AND CHARGED FOR EVERY STEP**: the walk holds
## MdLinks's cursors (the first `]` and `)` ahead, and the floor below which
## no email can start), which only ever move forward, so no suffix is
## scanned again from every `[` or `_`. Each step and each byte an inner
## scan reads is charged to the budget, and the walk stops as hostile the
## moment it is blown. The frozen work units (the judge's) are the
## charges' definition.
import Ascii
import Bytes
import MdChat
import MdHtml
import MdText
import MdMedia
import MdEmphasis
import MdLinks
import MdSafety

MdInline := [].{

	## What the pass reads. `Linked` turns the chat's `MSG_` reference (MdChat)
	## into its link, and `InLabel` leaves it text, as a link's label must be,
	## being inside an `<a>` already. `Document` has no reference, and its links
	## to other sites stay in their tab. A document also reads `<http://…>`,
	## leaves an email as text, and shows its images as its option says.
	##
	## `DocumentLabel` is a link's label in a document, where nothing may become a
	## second `<a>`: links and URLs stay text, and an image that would be a link
	## is its alt. `DocumentAlt` is an image's alt, which reads neither links nor
	## images. So a label costs at most two more passes, however its brackets nest.
	Refs : [
		Linked,
		InLabel,
		Document(MdSafety.Images),
		DocumentLabel(MdSafety.Images),
		DocumentAlt,
	]

	## `text` rendered onto `out`.
	render_onto : {
		out : List(U8),
		text : List(U8),
		refs : Refs,
		budget : MdText.Budget,
		uploads : MdSafety.Uploads,
	} -> Try(MdText.Rendered, [Hostile])
	render_onto = |
		{
			out,
			text,
			refs,
			budget,
			uploads,
		},
	| {
		len = text.len()
		is_document = refs != Linked and refs != InLabel
		reads_links = refs != DocumentLabel(Shown) and refs != DocumentLabel(AsLinks) and refs != DocumentAlt
		shows_images = refs == Document(Shown) or refs == DocumentLabel(Shown)
		alt_as_text = refs == DocumentLabel(AsLinks)
		outside = if (is_document) SameTab else NewTab
		label_refs = match refs {
			Document(images) => DocumentLabel(images)
			_ => InLabel
		}
		alt_refs = if (is_document) DocumentAlt else label_refs
		var $budget = budget
		var $pieces = []
		var $runs = []
		var $text_start = 0
		var $i = 0
		var $next_bracket = MdText.find_or_end(text, { byte: ']', at: 0 })
		var $brackets = if (is_document) Balanced(Unscanned) else FirstClose
		var $closes = Unscanned
		var $email_dead = 0
		while $i < len {
			$budget = MdText.charge($budget, 1)
			if MdText.is_blown($budget) {
				return Err(Hostile)
			} else {
				{}
			}
			c = MdText.at(text, $i)
			# Each byte class's scan says what it found (a `Step`); the step is
			# taken once, below. The chat's reference (MdChat) is read first,
			# whole.
			reference = if (refs == Linked) MdChat.reference_at(text, $i) else Err(NoRef)
			step = match reference {
				Ok(ref) => Token(Html(ref.html), ref.end)
				Err(NoRef) =>
					if c == '\\' and is_escapable(text, $i + 1) {
						Token(Text($i + 1, $i + 2), $i + 2)
					} else if c == '<' {
						match media_at(text, $i, uploads) {
							Ok(media) => Token(Html(media.html), media.end)
							Err(NotMedia) =>
								match if (is_document and reads_links) MdLinks.angle_url_at(text, $i) else Err(NotALink) {
									Ok(found) => Token(Html(MdLinks.autolink_html(found.url, Url, outside)), found.end)
									Err(NotALink) => Skip($i + 1)
								}
						}
					} else if c == '`' {
						scanned = code_span_at(text, { at: $i, budget: $budget })
						$budget = scanned.budget
						match scanned.span {
							Ok(span) => Token(Html(code_html(text, { start: span.content_start, end: span.content_end })), span.end)
							Err(NoClose) => {
								# No closing run of its length: the whole opening run is
								# literal, and is skipped, so no shorter run inside it
								# opens a span (CommonMark's runs are atomic). It stays
								# in the pending text.
								n = run_length(text, { byte: '`', at: $i })
								$budget = MdText.charge($budget, n)
								Skip($i + n)
							}
						}
					} else if c == '!' and text.get($i + 1) == Ok('[') and refs != DocumentAlt {
						# `![alt](src)`: an image where its src is an upload, else
						# the `!` is dropped and the `[` read as a link (MdSafety).
						linked = MdLinks.link_at(
							text,
							{
								at: $i + 1,
								next_bracket: $next_bracket,
								brackets: $brackets,
								closes: $closes,
								budget: $budget,
							},
						)
						$next_bracket = linked.next_bracket
						$brackets = linked.brackets
						$closes = linked.closes
						$budget = linked.budget
						image = match linked.link {
							Ok(link) =>
								match if (is_document) MdLinks.document_dest(link.url) else MdLinks.image_dest(link.url) {
									Ok(dest) => Ok({ link, dest })
									Err(NotAnImage) => Err(NotAnImage)
								}
							Err(NotALink) => Err(NotAnImage)
						}
						match image {
							Ok(found) =>
								if MdSafety.is_upload_url(found.dest.src, uploads) or ((shows_images or alt_as_text) and !MdSafety.is_dangerous_url(found.dest.src)) {
									# The alt is the label's inline content, its markup
									# gone (MdHtml.plain_text).
									alt = MdInline.render_onto({
										out: [],
										text: MdText.cut(text, found.link.label),
										refs: alt_refs,
										budget: $budget,
										uploads,
									})?
									$budget = alt.budget
									text_alt = MdHtml.plain_text(alt.out)
									html =
										if alt_as_text {
											Ok(MdText.escape_onto([], text_alt))
										} else if shows_images {
											MdLinks.shown_image({ src: found.dest.src, alt: text_alt, title: found.dest.title })
										} else {
											MdLinks.image({ src: found.dest.src, alt: text_alt, title: found.dest.title, uploads })
										}
									Token(Html(html ?? crash "MdInline.render_onto: an image the rules above let through"), found.link.end)
								} else if MdSafety.is_dangerous_url(found.dest.src) {
									# Refused: the whole image's source, `!` and all,
									# left in the pending text (MdSafety).
									Skip(found.link.end)
								} else {
									Cut($i + 1)
								}
							Err(NotAnImage) => Skip($i + 1)
						}
					} else if c == '[' and reads_links {
						linked = MdLinks.link_at(
							text,
							{
								at: $i,
								next_bracket: $next_bracket,
								brackets: $brackets,
								closes: $closes,
								budget: $budget,
							},
						)
						$next_bracket = linked.next_bracket
						$brackets = linked.brackets
						$closes = linked.closes
						$budget = linked.budget
						match linked.link {
							Ok(link) if is_refused_link(link.url, is_document) =>
							# Refused: the whole link's source left in the
							# pending text, nothing in it read (MdSafety).
								Skip(link.end)
							Ok(link) => {
								# The label is a line of its own, rendered inside the `<a>`.
								dest = link_dest(link.url, is_document)
								label = MdInline.render_onto({
									out: MdLinks.link_open(dest.src, { outside, title: dest.title }),
									text: MdText.cut(text, link.label),
									refs: label_refs,
									budget: $budget,
									uploads,
								})?
								$budget = label.budget
								Token(Html(label.out.concat(MdHtml.link_close)), link.end)
							}
							Err(NotALink) => Skip($i + 1)
						}
					} else if c == '*' or c == '_' or c == '~' {
						n = run_length(text, { byte: c, at: $i })
						$budget = MdText.charge($budget, n)
						run = MdEmphasis.delimiter_run(text, { start: $i, end: $i + n })
						# A `~` run that can neither open nor close (one `~`, three,
						# `~~` between spaces) is text: on the stack it would only
						# lengthen every look-back past it.
						if c == '~' and !run.can_open and !run.can_close {
							Skip($i + n)
						} else {
							$runs = $runs.append(run)
							Token(Run($runs.len() - 1), $i + n)
						}
					} else if reads_links and MdLinks.is_autolink_boundary(text, $i) {
						found = MdLinks.autolink_at(
							text,
							{
								at: $i,
								email_dead: $email_dead,
								emails: if (is_document) Plain else Linked,
								budget: $budget,
							},
						)
						$budget = found.budget
						$email_dead = found.email_dead
						match found.link {
							Ok(link) =>
								Token(
									Html(MdLinks.autolink_html(MdText.cut(text, { start: $i, end: link.end }), link.kind, outside)),
									link.end,
								)
							Err(NotALink) => Skip($i + 1)
						}
					} else {
						Skip($i + 1)
					}
			}
			# The one place the cursors move: a piece taken (the pending text
			# before it flushed), the pending text cut, or bytes left in it.
			match step {
				Token(piece, end) => {
					$pieces = with_token($pieces, { text_start: $text_start, at: $i, token: piece })
					$i = end
					$text_start = end
				}
				Cut(end) => {
					$pieces = flushed($pieces, { text_start: $text_start, at: $i })
					$i = end
					$text_start = end
				}
				Skip(end) => {
					$i = end
				}
			}
		}
		pieces = flushed($pieces, { text_start: $text_start, at: len })
		matched = MdEmphasis.emphasis({ runs: $runs, budget: $budget })?
		if MdText.is_blown(matched.budget) {
			Err(Hostile)
		} else {
			Ok({
				out: emit(
					out,
					{
						text,
						pieces,
						runs: matched.runs,
					},
				),
				budget: matched.budget,
			})
		}
	}
}

## What a link's destination says. A chat reads it whole, and a document reads a
## title and `<a b>` from it, or whole when it is neither.
link_dest : List(U8), Bool -> { src : List(U8), title : MdHtml.Title }
link_dest = |url, is_document| match if (is_document) MdLinks.document_dest(url) else Err(NotAnImage) {
	Ok(dest) => dest
	Err(NotAnImage) => { src: url, title: Untitled }
}

## A browser would run the destination, as written or as `link_dest` reads it.
is_refused_link : List(U8), Bool -> Bool
is_refused_link = |url, is_document| MdSafety.is_dangerous_url(url) or MdSafety.is_dangerous_url(link_dest(url, is_document).src)

## Whether the byte at `i` is ASCII punctuation, which a backslash before it
## escapes.
is_escapable : List(U8), U64 -> Bool
is_escapable = |text, i|
	match text.get(i) {
		Ok(c) => Ascii.is_punctuation(c)
		Err(OutOfBounds) => Bool.False
	}

## A piece of the line: text (a span of it, escaped when written), html made
## here, or a `*`/`_`/`~` run (by its index among the runs).
Piece : [
	Text(U64, U64),
	Html(List(U8)),
	Run(U64),
]

## The pending text from `text_start` up to `at`, as a piece when any.
flushed : List(Piece), { text_start : U64, at : U64 } -> List(Piece)
flushed = |pieces, { text_start, at }| if (at > text_start) pieces.append(Text(text_start, at)) else pieces

with_token : List(Piece),
{
	text_start : U64,
	at : U64,
	token : Piece,
} -> List(Piece)
with_token = |
	pieces,
	{
		text_start,
		at,
		token,
	},
| flushed(pieces, { text_start, at }).append(token)

## What one byte's scan found: a piece, ending at `end` (the pending text
## before it flushed first); the pending text cut at `end` with nothing taken
## (an image's dropped `!`); or bytes up to `end` left in the pending text.
Step : [
	Token(Piece, U64),
	Cut(U64),
	Skip(U64),
]

## A same-origin `<img>` or `<video>` at `at`, rebuilt (MdMedia).
media_at : List(U8), U64, MdSafety.Uploads -> Try(MdMedia.Rebuilt, [NotMedia])
media_at = |text, at, uploads|
	match MdMedia.img_at(text, at, uploads) {
		Ok(tag) => Ok(tag)
		Err(NotSafe) =>
			match MdMedia.video_at(text, at, uploads) {
				Ok(tag) => Ok(tag)
				Err(NotSafe) => Err(NotMedia)
			}
	}

## A code span's html: its content `text[start..end]`, as CommonMark trims
## it, escaped.
code_html : List(U8), { start : U64, end : U64 } -> List(U8)
code_html = |text, span| MdText.escape_onto(MdHtml.code_open, code_span_content(MdText.cut(text, span))).concat(MdHtml.code_close)

## How many `byte`s run from `at`.
run_length : List(U8), { byte : U8, at : U64 } -> U64
run_length = |text, { byte, at }| Bytes.count_while(text, { keep: |c| c == byte, at }) - at

## The pieces written out: text escaped, html as made, a run as its
## emphasis (MdEmphasis `run_onto`).
emit : List(U8),
{
	text : List(U8),
	pieces : List(Piece),
	runs : List(MdEmphasis.DelimiterRun),
} -> List(U8)
emit = |
	out,
	{
		text,
		pieces,
		runs,
	},
| {
	var $out = out
	for piece in pieces {
		$out = match piece {
			Text(start, end) => MdText.escape_onto($out, MdText.cut(text, { start, end }))
			Html(html) => $out.concat(html)
			Run(k) => MdEmphasis.run_onto($out, MdEmphasis.run_at(runs, k))
		}
	}
	$out
}

# ── code spans ──

## The backtick run at `at` closed by a run of
## exactly its length, its content's span, and the index past the close.
code_span_at : List(U8),
{
	at : U64,
	budget : MdText.Budget,
} -> {
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
code_span_at = |text, { at, budget }| {
	len = text.len()
	n = run_length(text, { byte: '`', at })
	var $budget = MdText.charge(budget, n)
	var $k = at + n
	while $k < len {
		$budget = MdText.charge($budget, 1)
		if MdText.at(text, $k) != '`' {
			$k = $k + 1
		} else {
			m = run_length(text, { byte: '`', at: $k })
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

## One space off each end when both ends
## are spaces and it is not all spaces.
code_span_content : List(U8) -> List(U8)
code_span_content = |content| {
	n = content.len()
	if n >= 2 and content.first() == Ok(' ') and content.last() == Ok(' ') and content.any(|c| c != ' ') {
		MdText.cut(content, { start: 1, end: n - 1 })
	} else {
		content
	}
}

inline : Str -> Str
inline = |text| match MdInline.render_onto({
	out: [],
	text: text.to_utf8(),
	refs: Linked,
	budget: MdText.unlimited,
	uploads: MdSafety.under("/user_uploads/".to_utf8()),
}) {
	Ok(r) => Str.from_utf8(r.out) ?? "not text"
	Err(Hostile) => "hostile"
}

expect inline("**bold** and *italic* together") == "<strong>bold</strong> and <em>italic</em> together"
expect inline("a**b**c") == "a<strong>b</strong>c"
expect inline("***x***") == "<em><strong>x</strong></em>"
expect inline("see MSG_plans_3 now") == "see <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a> now"
expect inline("[about MSG_plans_3](https://example.org)") == "<a href=\"https://example.org\" target=\"_blank\" rel=\"noopener\">about MSG_plans_3</a>"
expect inline("[x](java\tscript:alert(1))") == "[x](java\tscript:alert(1))"
expect inline("`a<b`") == "<code>a&lt;b</code>"
expect inline("go to www.a.com, now") == "go to <a href=\"http://www.a.com\" target=\"_blank\" rel=\"noopener\">www.a.com</a>, now"
expect inline("mail a.b@c.d.") == "mail <a href=\"mailto:a.b@c.d\">a.b@c.d</a>."
# A host without a dot is no autolink: `localhost` is a word.
expect inline("http://localhost:9100/x.md") == "http://localhost:9100/x.md"
# The floor keys on a closer's can_open and its run's length as written
# (CommonMark's, commonmark.js's and markdown-it's).
expect inline("*a**b** c**") == "<em>a<strong>b</strong> c</em>*"
expect inline("x **a*a*a*") == "x *<em>a<em>a</em>a</em>"
# Keyed on the length alone, this one would move; on both, it does not.
expect inline("x **a*a****") == "x <strong>a<em>a</em></strong>*"
# GFM's strikethrough: two tildes, on one line, flanking as `*` does.
expect inline("~~Hi~~ Hello, world!") == "<del>Hi</del> Hello, world!"
expect inline("a ~~**b**~~ c") == "a <del><strong>b</strong></del> c"
expect inline("~one~ and ~~~three~~~ stay") == "~one~ and ~~~three~~~ stay"
expect inline("about ~~ 5 ~~ or ~5 minutes") == "about ~~ 5 ~~ or ~5 minutes"
expect inline("~~a *b~~ c*") == "<del>a *b</del> c*"
# Backslash escapes: before ASCII punctuation, the character is text.
expect inline("\\*not em\\* and \\[not](a link) \\`not code\\`") == "*not em* and [not](a link) `not code`"
expect inline("[a](/b\\*c)") == "<a href=\"/b*c\">a</a>"
expect inline("[a](javascript\\:alert(1))") == "[a](javascript\\:alert(1))"
expect inline("![a *cat*](/user_uploads/cat.png \"the cat\")") == "<img src=\"/user_uploads/cat.png\" alt=\"a cat\" title=\"the cat\">"
expect inline("see ![](/user_uploads/x.png)!") == "see <img src=\"/user_uploads/x.png\" alt=\"\">!"
expect inline("![off](https://evil.example/x.png)") == "<a href=\"https://evil.example/x.png\" target=\"_blank\" rel=\"noopener\">off</a>"
expect inline("![js](javascript:alert(1))") == "![js](javascript:alert(1))"
expect inline("![a](//evil/x.png)") == "<a href=\"//evil/x.png\">a</a>"
expect inline("![a \"q\" & <b>](/user_uploads/x.png)") == "<img src=\"/user_uploads/x.png\" alt=\"a &quot;q&quot; &amp; &lt;b&gt;\">"
expect inline("![a](/x.png bad)") == "!<a href=\"/x.png bad\">a</a>"
expect inline("\\![a](/x.png)") == "!<a href=\"/x.png\">a</a>"
expect inline("![no close") == "![no close"
expect inline("![stream](/conversations/1/stream)") == "<a href=\"/conversations/1/stream\">stream</a>"
expect inline("\\~~not struck~~") == "~~not struck~~"
expect inline("a\\b \\\\ \\") == "a\\b \\ \\"
expect inline("`\\*` stays") == "<code>\\*</code> stays"
expect inline("\\<b> and \\&amp;") == "&lt;b&gt; and &amp;amp;"
