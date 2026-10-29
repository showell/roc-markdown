## **THE INLINE PASS** (chat-markdown markdown_inline.zig): one line of inline content to
## HTML. The line is cut into pieces (text to escape; html made here, for a
## code span, a same-origin `<img>` or `<video>` (MdMedia), a `[t](u)` link
## or an autolink (MdLinks), or the chat's `MSG_` reference (MdChat); and
## `*`/`_` runs), the
## runs are matched into `<em>` and `<strong>` (MdEmphasis), and the pieces
## are written out. Pure.
##
## **LINEAR BY ITS CURSORS, AND CHARGED FOR EVERY STEP**: the walk holds
## MdLinks's cursors (the first `]` and `)` ahead, and the floor below which
## no email can start), which only ever move forward, so no suffix is
## scanned again from every `[` or `_`. Each step and each byte an inner
## scan reads is charged to the budget, and the walk stops as hostile the
## moment it is blown: the Zig's charges, unit for unit, so a message the
## Zig refuses is a message this refuses.
import Bytes
import MdChat
import MdHtml
import MdText
import MdMedia
import MdEmphasis
import MdLinks

MdInline := [].{

	## markdown_inline `renderInline`: `text` rendered onto `out`. `Linked`
	## turns the chat's `MSG_` reference (MdChat) into its link; `InLabel` leaves it text, as a
	## link's label must be, being inside an `<a>` already.
	render_onto : {
		out : List(U8),
		text : List(U8),
		refs : [Linked, InLabel],
		budget : MdText.Budget,
	} -> Try(MdText.Rendered, [Hostile])
	render_onto = |
		{
			out,
			text,
			refs,
			budget,
		},
	| {
		len = List.len(text)
		var $budget = budget
		var $pieces = []
		var $runs = []
		var $run_start = 0
		var $i = 0
		var $rb = MdText.find_or_end(text, { byte: ']', at: 0 })
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
			# The chat's reference (MdChat) is read first, whole.
			reference = if refs == Linked MdChat.reference_at(text, $i) else Err(NoRef)
			match reference {
				Ok(ref) => {
					$pieces = with_token(
						$pieces,
						{
							run_start: $run_start,
							at: $i,
							token: Html(ref.html),
						},
					)
					$i = ref.end
					$run_start = ref.end
				}
				Err(NoRef) =>
					if c == '<' {
						match MdMedia.img_at(text, $i) {
							Ok(tag) => {
								$pieces = with_token(
									$pieces,
									{
										run_start: $run_start,
										at: $i,
										token: Html(tag.html),
									},
								)
								$i = tag.end
								$run_start = tag.end
							}
							Err(NotSafe) =>
								match MdMedia.video_at(text, $i) {
									Ok(tag) => {
										$pieces = with_token(
											$pieces,
											{
												run_start: $run_start,
												at: $i,
												token: Html(tag.html),
											},
										)
										$i = tag.end
										$run_start = tag.end
									}
									Err(NotSafe) => {
										$i = $i + 1
									}
								}
						}
					} else if c == '`' {
						scanned = code_span_at(text, { at: $i, budget: $budget })
						$budget = scanned.budget
						match scanned.span {
							Ok(span) => {
								code = code_span_content(
									MdText.cut(
										text,
										{ start: span.content_start, end: span.content_end },
									),
								)
								$pieces = with_token(
									$pieces,
									{
										run_start: $run_start,
										at: $i,
										token: Html(
											List.concat(
												MdText.escape_onto(MdHtml.code_open, code),
												MdHtml.code_close,
											),
										),
									},
								)
								$i = span.end
								$run_start = span.end
							}
							Err(NoClose) => {
								# No closing run of its length: the whole opening run is
								# literal, and is skipped, so no shorter run inside it
								# opens a span (CommonMark's runs are atomic). It stays
								# in the pending text.
								n = run_length(text, { byte: '`', at: $i })
								$budget = MdText.charge($budget, n)
								$i = $i + n
							}
						}
					} else if c == '[' {
						linked = MdLinks.link_at(
							text,
							{
								at: $i,
								rb: $rb,
								closes: $closes,
								budget: $budget,
							},
						)
						$rb = linked.rb
						$closes = linked.closes
						$budget = linked.budget
						match linked.link {
							Ok(link) => {
								# The label is a line of its own, rendered `InLabel`
								# inside the `<a>`.
								label = MdInline.render_onto({
									out: MdLinks.link_open(link.url),
									text: MdText.cut(text, link.label),
									refs: InLabel,
									budget: $budget,
								})?
								$budget = label.budget
								$pieces = with_token(
									$pieces,
									{
										run_start: $run_start,
										at: $i,
										token: Html(List.concat(label.out, MdHtml.link_close)),
									},
								)
								$i = link.end
								$run_start = link.end
							}
							Err(NotALink) => {
								$i = $i + 1
							}
						}
					} else if c == '*' or c == '_' {
						$pieces = flushed($pieces, { run_start: $run_start, at: $i })
						n = run_length(text, { byte: c, at: $i })
						$budget = MdText.charge($budget, n)
						$pieces = List.append($pieces, Run(List.len($runs)))
						$runs = List.append($runs, MdEmphasis.delimiter_run(text, { start: $i, end: $i + n }))
						$i = $i + n
						$run_start = $i
					} else if MdLinks.is_autolink_boundary(text, $i) {
						found = MdLinks.autolink_at(
							text,
							{
								at: $i,
								email_dead: $email_dead,
								budget: $budget,
							},
						)
						$budget = found.budget
						$email_dead = found.email_dead
						match found.link {
							Ok(link) => {
								$pieces = with_token(
									$pieces,
									{
										run_start: $run_start,
										at: $i,
										token: Html(
											MdLinks.autolink_html(
												MdText.cut(text, { start: $i, end: link.end }),
												link.kind,
											),
										),
									},
								)
								$i = link.end
								$run_start = link.end
							}
							Err(NotALink) => {
								$i = $i + 1
							}
						}
					} else {
						$i = $i + 1
					}
			}
		}
		pieces = flushed($pieces, { run_start: $run_start, at: len })
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

## A piece of the line: text (a span of it, escaped when written), html made
## here, or a `*`/`_` run (by its index among the runs).
Piece : [
	Text(U64, U64),
	Html(List(U8)),
	Run(U64),
]

## The pending text from `run_start` up to `at`, as a piece when any.
flushed : List(Piece), { run_start : U64, at : U64 } -> List(Piece)
flushed = |pieces, { run_start, at }| if at > run_start List.append(
	pieces,
	Text(run_start, at),
) else pieces

with_token : List(Piece),
{
	run_start : U64,
	at : U64,
	token : Piece,
} -> List(Piece)
with_token = |
	pieces,
	{
		run_start,
		at,
		token,
	},
| List.append(flushed(pieces, { run_start, at }), token)

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
			Html(html) => List.concat($out, html)
			Run(k) => MdEmphasis.run_onto($out, MdEmphasis.run_at(runs, k))
		}
	}
	$out
}

# ── code spans ──

## markdown_inline `codeSpanAt`: the backtick run at `at` closed by a run of
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
	len = List.len(text)
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

## markdown_inline `codeSpanContent`: one space off each end when both ends
## are spaces and it is not all spaces.
code_span_content : List(U8) -> List(U8)
code_span_content = |content| {
	n = List.len(content)
	if n >= 2 and List.first(content) == Ok(' ') and List.last(content) == Ok(' ') and List.any(
		content,
		|c| c != ' ',
	) {
		MdText.cut(content, { start: 1, end: n - 1 })
	} else {
		content
	}
}

inline : Str -> Str
inline = |text| match MdInline.render_onto({
	out: [],
	text: Str.to_utf8(text),
	refs: Linked,
	budget: MdText.unlimited,
}) {
	Ok(r) => Str.from_utf8(r.out) ?? "not text"
	Err(Hostile) => "hostile"
}

expect inline("**bold** and *italic* together") == "<strong>bold</strong> and <em>italic</em> together"
expect inline("a**b**c") == "a<strong>b</strong>c"
expect inline("***x***") == "<em><strong>x</strong></em>"
expect inline("see MSG_plans_3 now") == "see <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a> now"
expect inline("[about MSG_plans_3](https://example.org)") == "<a href=\"https://example.org\" target=\"_blank\" rel=\"noopener\">about MSG_plans_3</a>"
expect inline("[x](java\tscript:alert(1))") == "<a href=\"\">x</a>"
expect inline("`a<b`") == "<code>a&lt;b</code>"
expect inline("go to www.a.com, now") == "go to <a href=\"http://www.a.com\" target=\"_blank\" rel=\"noopener\">www.a.com</a>, now"
expect inline("mail a.b@c.d.") == "mail <a href=\"mailto:a.b@c.d\">a.b@c.d</a>."
expect inline("http://localhost:9100/x.md") == "http://localhost:9100/x.md"
# The floor keys on a closer's can_open and its run's length as written
# (CommonMark's, commonmark.js's and markdown-it's).
expect inline("*a**b** c**") == "<em>a<strong>b</strong> c</em>*"
expect inline("x **a*a*a*") == "x *<em>a<em>a</em>a</em>"
# Keyed on the length alone, this one would move; on both, it does not.
expect inline("x **a*a****") == "x <strong>a<em>a</em></strong>*"
