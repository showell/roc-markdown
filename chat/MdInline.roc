## **THE INLINE PASS** (chat-markdown markdown_inline.zig, with the rules of
## markdown_links.zig, whose one caller it is): one line of inline content
## to HTML. The line is cut into pieces (text to escape; html made here, for
## a code span, a same-origin `<img>` or `<video>`, a `[t](u)` link, an
## autolink or a `MSG_` reference; and `*`/`_` runs), the runs are matched
## into `<em>` and `<strong>` by CommonMark's delimiter stack, and the
## pieces are written out. Pure.
##
## **LINEAR BY ITS CURSORS, AND CHARGED FOR EVERY STEP**: the first `]` and
## `)` ahead, and the floor below which no email can start, only ever move
## forward, so no suffix is scanned again from every `[` or `_`. Each step
## and each byte an inner scan reads is charged to the budget, and the walk
## stops as hostile the moment it is blown: the Zig's charges, unit for
## unit, so a message the Zig refuses is a message this refuses.
import Ascii
import Bytes
import MdText
import MdMedia

MdInline := [].{

	## markdown_inline `renderInline`: `text` rendered onto `out`. `Linked`
	## turns a `MSG_` reference into its link; `InLabel` leaves it text, as a
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
		var $rp = MdText.find_or_end(text, { byte: ')', at: 0 })
		var $email_dead = 0
		while $i < len {
			$budget = MdText.charge($budget, 1)
			if MdText.is_blown($budget) {
				return Err(Hostile)
			} else {
				{}
			}
			c = MdText.at(text, $i)
			# A MSG_ reference is read first, whole: its `_`s would otherwise
			# be read as emphasis and split it.
			ref_end = if refs == Linked and c == 'M' msg_ref_end(text, $i) else Err(NoRef)
			match ref_end {
				Ok(end) => {
					$pieces = with_token(
						$pieces,
						{
							run_start: $run_start,
							at: $i,
							token: Html(msg_ref(MdText.cut(text, { start: $i + 4, end }))),
						},
					)
					$i = end
					$run_start = end
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
												MdText.escape_onto(code_open, code),
												code_close,
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
						linked = link_at(
							text,
							{
								at: $i,
								rb: $rb,
								rp: $rp,
								budget: $budget,
							},
						)?
						$rb = linked.rb
						$rp = linked.rp
						$budget = linked.budget
						match linked.link {
							Ok(link) => {
								$pieces = with_token(
									$pieces,
									{
										run_start: $run_start,
										at: $i,
										token: Html(link.html),
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
						flank = flanking(text, { start: $i, end: $i + n })
						# An `_` run inside a word neither opens nor closes.
						is_star = c == '*'
						can_open = flank.left and (is_star or !flank.right or flank.before_punct)
						can_close = flank.right and (is_star or !flank.left or flank.after_punct)
						$pieces = List.append($pieces, Run(List.len($runs)))
						$runs = List.append(
							$runs,
							{
								char: c,
								count: n,
								orig: n,
								can_open,
								can_close,
								below: Edge,
								above: Edge,
								opens: [],
								closes: [],
							},
						)
						$i = $i + n
						$run_start = $i
					} else if is_autolink_boundary(text, $i) {
						found = autolink_at(
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
											autolink_html(
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
		matched = emphasis({ runs: $runs, budget: $budget })?
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

## A run's neighbour on the delimiter stack: another run, or the edge.
Link : [Edge, At(U64)]

## A `*`/`_` run: its character, the delimiters it has left and had, whether
## it may open and close, its neighbours on the stack (`below` is earlier),
## and the emphasis it opens after it and closes before it, each `1`
## (`<em>`) or `2` (`<strong>`), in the order matched.
Run : {
	char : U8,
	count : U64,
	orig : U64,
	can_open : Bool,
	can_close : Bool,
	below : Link,
	above : Link,
	opens : List(U64),
	closes : List(U64),
}

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

## The pieces written out: text escaped, html as made, a run as the emphasis
## it closes, its delimiters left, and the emphasis it opens, innermost
## nearest. (The Zig splices marker nodes into its linked list beside each
## run; a marker is only ever spliced beside a run, so a run's own lists, in
## this order, are the same sequence.)
emit : List(U8),
{
	text : List(U8),
	pieces : List(Piece),
	runs : List(Run),
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
			Run(k) => {
				run = run_at(runs, k)
				var $o = $out
				for use in run.closes {
					$o = List.concat($o, if use == 2 strong_close else em_close)
				}
				$o = List.concat($o, List.repeat(run.char, run.count))
				var $n = List.len(run.opens)
				while $n > 0 {
					$n = $n - 1
					$o = List.concat(
						$o,
						if (List.get(run.opens, $n) ?? 0) == 2 strong_open else em_open,
					)
				}
				$o
			}
		}
	}
	$out
}

run_at : List(Run), U64 -> Run
run_at = |runs, k| match List.get(runs, k) {
	Ok(run) => run
	Err(OutOfBounds) => crash "MdInline: a run's index past the runs"
}

index_of : Link -> U64
index_of = |link| match link {
	At(k) => k
	Edge => crash "MdInline: the stack's edge read as a run"
}

set_run : List(Run), { at : U64, run : Run } -> List(Run)
set_run = |runs, { at, run }| List.set(
	runs,
	at,
	run,
) ?? crash "MdInline: a run set past the runs"

## markdown_inline `processEmphasis`: the runs matched into emphasis by
## CommonMark's delimiter stack, the rule of 3 included. One unit per
## closer visited and per opener looked back at; blown on a closer is
## hostile, and the caller checks once more after.
emphasis : { runs : List(Run), budget : MdText.Budget } -> Try(
	{ runs : List(Run), budget : MdText.Budget },
	[Hostile],
)
emphasis = |{ runs, budget }| {
	n = List.len(runs)
	var $runs = List.map_with_index(
		runs,
		|run, k| {
			..run,
			below: if k == 0 Edge else At(k - 1),
			above: if k + 1 == n Edge else At(k + 1),
		},
	)
	var $budget = budget
	# The lowest opener a closer may look back to, by its count mod 3 and
	# its character (`*` then `_`): an edge is the stack's bottom.
	var $bottoms = List.repeat(Edge, 6)
	var $closer = if n == 0 Edge else At(0)
	while $closer != Edge {
		ci = index_of($closer)
		$budget = MdText.charge($budget, 1)
		if MdText.is_blown($budget) {
			return Err(Hostile)
		} else {
			{}
		}
		closer = run_at($runs, ci)
		if !closer.can_close {
			$closer = closer.above
		} else {
			slot = (closer.count % 3) * 2 + (if closer.char == '*' 0 else 1)
			bottom = List.get($bottoms, slot) ?? Edge
			var $opener = closer.below
			var $found = Bool.False
			while $opener != Edge {
				$budget = MdText.charge($budget, 1)
				if $opener == bottom {
					break
				} else {
					{}
				}
				opener = run_at($runs, index_of($opener))
				# The rule of 3: a run that may both open and close matches
				# another only when their lengths' sum is no multiple of 3,
				# unless both are.
				is_both = closer.can_open or opener.can_close
				odd = is_both and closer.orig % 3 != 0 and (opener.orig + closer.orig) % 3 == 0
				if opener.can_open and opener.char == closer.char and !odd {
					$found = Bool.True
					break
				} else {
					{}
				}
				$opener = opener.below
			}
			if $found {
				oi = index_of($opener)
				opener = run_at($runs, oi)
				use = if opener.count >= 2 and closer.count >= 2 2 else 1
				# Every run strictly between the two leaves the stack.
				$runs = set_run(
					$runs,
					{
						at: oi,
						run: {
							..opener,
							count: opener.count - use,
							above: At(ci),
							opens: List.append(opener.opens, use),
						},
					},
				)
				$runs = set_run(
					$runs,
					{
						at: ci,
						run: {
							..closer,
							count: closer.count - use,
							below: At(oi),
							closes: List.append(closer.closes, use),
						},
					},
				)
				if opener.count == use {
					$runs = unlinked($runs, oi)
				} else {
					{}
				}
				if closer.count == use {
					above = run_at($runs, ci).above
					$runs = unlinked($runs, ci)
					$closer = above
				} else {
					{}
				}
				# A closer with delimiters left is looked at again.
			} else {
				$closer = closer.above
				$bottoms = List.set(
					$bottoms,
					slot,
					closer.below,
				) ?? crash "MdInline: a bottom's slot past six"
				if !closer.can_open {
					$runs = unlinked($runs, ci)
				} else {
					{}
				}
			}
		}
	}
	Ok({ runs: $runs, budget: $budget })
}

## markdown_inline `unlinkDelim`: run `k` off the stack; its place among the
## pieces, and its delimiters left, stay.
unlinked : List(Run), U64 -> List(Run)
unlinked = |runs, k| {
	run = run_at(runs, k)
	with_below = match run.below {
		At(b) => set_run(runs, { at: b, run: { ..run_at(runs, b), above: run.above } })
		Edge => runs
	}
	match run.above {
		At(a) => set_run(with_below, { at: a, run: { ..run_at(with_below, a), below: run.below } })
		Edge => with_below
	}
}

## markdown_inline `flanking`: CommonMark's left- and right-flanking for the
## run `text[start..end]`; the line's ends count as space.
flanking : List(U8),
{
	start : U64,
	end : U64,
} -> {
	left : Bool,
	right : Bool,
	before_punct : Bool,
	after_punct : Bool,
}
flanking = |text, { start, end }| {
	before = if start == 0 ' ' else MdText.at(text, start - 1)
	after = if end >= List.len(text) ' ' else MdText.at(text, end)
	before_space = MdText.is_space(before)
	after_space = MdText.is_space(after)
	before_punct = Ascii.is_punctuation(before)
	after_punct = Ascii.is_punctuation(after)
	{
		left: !after_space and (!after_punct or before_space or before_punct),
		right: !before_space and (!before_punct or after_space or after_punct),
		before_punct,
		after_punct,
	}
}

# ── MSG_ references (markdown_links) ──

## markdown_links `msgRefEnd`: `\bMSG_([A-Za-z0-9-]+_[0-9]+)\b` at `i`, and
## the index past it.
msg_ref_end : List(U8), U64 -> Try(U64, [NoRef])
msg_ref_end = |text, i| {
	len = List.len(text)
	if i + 4 > len or MdText.cut(text, { start: i, end: i + 4 }) != msg_prefix {
		Err(NoRef)
	} else if i > 0 and MdText.is_word_char(MdText.at(text, i - 1)) {
		Err(NoRef)
	} else {
		slug_end = Bytes.count_while(text, { keep: MdText.is_slug_char, at: i + 4 })
		if slug_end == i + 4 or slug_end >= len or MdText.at(text, slug_end) != '_' {
			Err(NoRef)
		} else {
			end = Bytes.count_while(text, { keep: Ascii.is_digit, at: slug_end + 1 })
			if end == slug_end + 1 or (
				end < len and MdText.is_word_char(
					MdText.at(
						text,
						end,
					),
				)
			) Err(NoRef) else Ok(end)
		}
	}
}

## markdown_links `appendMsgRef`: the reference's link. Its slug grammar has
## no byte HTML gives a meaning, so it is written as it is.
msg_ref : List(U8) -> List(U8)
msg_ref = |slug| List.join([
	Str.to_utf8("<a href=\"#msg-"),
	slug,
	Str.to_utf8("\" class=\"msg-ref\">MSG_"),
	slug,
	Str.to_utf8("</a>"),
])

## markdown_links `isExternalHref`: a `scheme://…` href, which opens in a
## new tab. `#msg-…`, `/chat/…` and `mailto:` are not.
is_external_href : List(U8) -> Bool
is_external_href = |href| match Bytes.find(href, { needle: scheme_end }) {
	Ok(p) =>
		p > 0 and Ascii.is_letter(MdText.at(href, 0)) and List.all(
			MdText.cut(href, { start: 1, end: p }),
			|c| Ascii.is_alphanumeric(c) or c == '+' or c == '.' or c == '-',
		)
	Err(NotFound) => Bool.False
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

# ── [t](u) links ──

## markdown_inline `mdLinkAt`: the link `[label](url)` at `at`, rendered,
## and the index past its `)`. `rb` and `rp`, the first `]` and `)` the
## line has not yet passed, only move forward, so the scans cost the line's
## length in all, not once a `[`. The label renders `InLabel`.
link_at : List(U8),
{
	at : U64,
	rb : U64,
	rp : U64,
	budget : MdText.Budget,
} -> Try(
	{
		link : Try({ html : List(U8), end : U64 }, [NotALink]),
		rb : U64,
		rp : U64,
		budget : MdText.Budget,
	},
	[Hostile],
)
link_at = |
	text,
	{
		at,
		rb,
		rp,
		budget,
	},
| {
	len = List.len(text)
	var $rb = rb
	var $rp = rp
	var $budget = budget
	while $rb < len and $rb < at + 1 {
		from = $rb
		$rb = MdText.find_or_end(text, { byte: ']', at: $rb + 1 })
		$budget = MdText.charge($budget, $rb - from)
	}
	if $rb >= len or $rb + 1 >= len or MdText.at(text, $rb + 1) != '(' {
		Ok({
			link: Err(NotALink),
			rb: $rb,
			rp: $rp,
			budget: $budget,
		})
	} else {
		close_bracket = $rb
		open_paren = close_bracket + 1
		while $rp < len and $rp < open_paren + 1 {
			from = $rp
			$rp = MdText.find_or_end(text, { byte: ')', at: $rp + 1 })
			$budget = MdText.charge($budget, $rp - from)
		}
		if $rp >= len {
			Ok({
				link: Err(NotALink),
				rb: $rb,
				rp: $rp,
				budget: $budget,
			})
		} else {
			close_paren = $rp
			url = MdText.cut(text, { start: open_paren + 1, end: close_paren })
			href = if is_dangerous_url(url) a_open else MdText.escape_onto(a_open, url)
			head = List.join([
				href,
				['"'],
				if is_external_href(url) external_attrs else [],
				['>'],
			])
			label = MdInline.render_onto({
				out: head,
				text: MdText.cut(text, { start: at + 1, end: close_bracket }),
				refs: InLabel,
				budget: $budget,
			})?
			Ok({
				link: Ok({ html: List.concat(label.out, a_close), end: close_paren + 1 }),
				rb: $rb,
				rp: $rp,
				budget: label.budget,
			})
		}
	}
}

## markdown_inline `isDangerousUrl`: `javascript:`, `vbscript:`, `file:`,
## and `data:` but for an image's, **READ AS A BROWSER READS IT** (metal-vmm
## QUEUE 172): its ends' control bytes and spaces dropped, and every tab
## and newline inside, before the scheme is looked for. Only its first 32
## bytes so read count.
is_dangerous_url : List(U8) -> Bool
is_dangerous_url = |raw| {
	start = Bytes.count_while(raw, { keep: |c| c <= ' ', at: 0 })
	trimmed = List.drop_first(raw, start)
	kept = List.drop_last(trimmed, Bytes.count_back(trimmed, |c| c <= ' '))
	var $seen = []
	for c in kept {
		if c == '\t' or c == '\n' or c == '\r' or List.len($seen) == 32 {
			{}
		} else {
			$seen = List.append($seen, c)
		}
	}
	url = $seen
	starts_with = |prefix| MdText.is_prefixed_ignoring_case(
		url,
		{ at: 0, prefix: Str.to_utf8(prefix) },
	)
	if starts_with("data:image/") {
		!List.any(
			[
				"png",
				"gif",
				"jpeg",
				"webp",
				"svg",
			],
			|kind| MdText.is_prefixed_ignoring_case(url, { at: 11, prefix: Str.to_utf8(kind) }),
		)
	} else {
		List.any(dangerous_schemes, starts_with)
	}
}

# ── autolinks ──

## markdown_inline `autolinkBoundary`: an autolink starts only at the line's
## start, or after a space or one of `*`, `_`, `~` and `(`.
is_autolink_boundary : List(U8), U64 -> Bool
is_autolink_boundary = |text, i|
	if i == 0 {
		Bool.True
	} else {
		p = MdText.at(text, i - 1)
		MdText.is_space(p) or p == '*' or p == '_' or p == '~' or p == '('
	}

AutoKind : [
	Url,
	Www,
	Email,
]

## markdown_inline `autolinkAt`: a GFM autolink at `at`, and the index past
## it. `email_dead` is the floor below which no email can start: when one
## fails, every position in its local part fails the same way, so the floor
## moves past it (without it, `a_b_a_b…` is quadratic).
autolink_at : List(U8),
{
	at : U64,
	email_dead : U64,
	budget : MdText.Budget,
} -> {
	link : Try({ end : U64, kind : AutoKind }, [NotALink]),
	email_dead : U64,
	budget : MdText.Budget,
}
autolink_at = |
	text,
	{
		at,
		email_dead,
		budget,
	},
| {
	starts_with = |prefix| MdText.is_prefixed_ignoring_case(
		text,
		{ at, prefix: Str.to_utf8(prefix) },
	)
	if starts_with("http://") or starts_with("https://") {
		u = url_end(text, { start: at, budget })
		{
			link: u.end.map_ok(|end| { end, kind: Url }),
			email_dead,
			budget: u.budget,
		}
	} else if starts_with("www.") {
		u = url_end(text, { start: at, budget })
		{
			link: u.end.map_ok(|end| { end, kind: Www }),
			email_dead,
			budget: u.budget,
		}
	} else if at >= email_dead {
		e = email_end(text, { start: at, budget })
		match e.end {
			Ok(end) => {
				link: Ok({ end, kind: Email }),
				email_dead,
				budget: e.budget,
			}
			Err(NotALink) => {
				j = Bytes.count_while(text, { keep: is_email_local_char, at })
				{
					link: Err(NotALink),
					email_dead: if j > at j else at + 1,
					budget: MdText.charge(e.budget, j - at),
				}
			}
		}
	} else {
		{
			link: Err(NotALink),
			email_dead,
			budget,
		}
	}
}

## markdown_inline `urlEnd`: URL bytes from `start` up to a space or `<`,
## less GFM's trailing punctuation and any `)` without its `(`. The host
## (after the scheme, before a port, path, query or fragment) must hold a
## `.`.
url_end : List(U8),
{ start : U64, budget : MdText.Budget } -> {
	end : Try(U64, [NotALink]),
	budget : MdText.Budget,
}
url_end = |text, { start, budget }| {
	scanned = Bytes.count_while(text, { keep: |c| !MdText.is_space(c) and c != '<', at: start })
	spent = MdText.charge(budget, scanned - start)
	url = MdText.cut(text, { start, end: scanned })
	host_start = match Bytes.find(url, { needle: scheme_end }) {
		Ok(p) => p + 3
		Err(NotFound) => 0
	}
	host_end = Bytes.count_while(
		url,
		{ keep: |c| c != '/' and c != '?' and c != '#' and c != ':', at: host_start },
	)
	if !List.contains(
		MdText.cut(url, { start: host_start, end: U64.max(host_start, host_end) }),
		'.',
	) {
		{ end: Err(NotALink), budget: spent }
	} else {
		opens = List.count_if(url, |c| c == '(')
		var $closes = List.count_if(url, |c| c == ')')
		var $end = scanned
		while $end > start {
			c = MdText.at(text, $end - 1)
			if List.contains(trailing_punct, c) {
				$end = $end - 1
			} else if c == ')' and $closes > opens {
				$end = $end - 1
				$closes = $closes - 1
			} else {
				break
			}
		}
		{ end: if $end <= start + 4 Err(NotALink) else Ok($end), budget: spent }
	}
}

## markdown_inline `emailEnd`: `local@domain.tld` at `start`, a trailing
## `.`, `-` or `_` not its.
email_end : List(U8),
{ start : U64, budget : MdText.Budget } -> {
	end : Try(U64, [NotALink]),
	budget : MdText.Budget,
}
email_end = |text, { start, budget }| {
	local_end = Bytes.count_while(text, { keep: is_email_local_char, at: start })
	local_spent = MdText.charge(budget, local_end - start)
	if local_end == start or local_end >= List.len(text) or MdText.at(text, local_end) != '@' {
		{ end: Err(NotALink), budget: local_spent }
	} else {
		domain_start = local_end + 1
		domain_end = Bytes.count_while(
			text,
			{
				keep: |c| Ascii.is_alphanumeric(c) or c == '.' or c == '-' or c == '_',
				at: domain_start,
			},
		)
		spent = MdText.charge(local_spent, domain_end - domain_start)
		if domain_end == domain_start or !List.contains(
			MdText.cut(text, { start: domain_start, end: domain_end }),
			'.',
		) {
			{ end: Err(NotALink), budget: spent }
		} else {
			var $j = domain_end
			while $j > domain_start and List.contains(
				[
					'.',
					'-',
					'_',
				],
				MdText.at(text, $j - 1),
			) {
				$j = $j - 1
			}
			{ end: Ok($j), budget: spent }
		}
	}
}

is_email_local_char : U8 -> Bool
is_email_local_char = |c| Ascii.is_alphanumeric(c) or c == '.' or c == '_' or c == '+' or c == '-'

## markdown_inline `emitAutolink`: the link, a URL's and a `www.`'s opening
## in a new tab, an email's as `mailto:`.
autolink_html : List(U8), AutoKind -> List(U8)
autolink_html = |link, kind| {
	href = match kind {
		Url => MdText.escape_onto(a_open, link)
		Www => MdText.escape_onto(List.concat(a_open, Str.to_utf8("http://")), link)
		Email => MdText.escape_onto(List.concat(a_open, Str.to_utf8("mailto:")), link)
	}
	head = List.join([
		href,
		['"'],
		if kind == Email [] else external_attrs,
		['>'],
	])
	List.concat(MdText.escape_onto(head, link), a_close)
}

## markdown_links `external_attrs`: a new tab, without the opener.
external_attrs : List(U8)
external_attrs = Str.to_utf8(" target=\"_blank\" rel=\"noopener\"")

dangerous_schemes : List(Str)
dangerous_schemes = [
	"javascript:",
	"vbscript:",
	"file:",
	"data:",
]

trailing_punct : List(U8)
trailing_punct = Str.to_utf8("?!.,:*_~'\"")

scheme_end : List(U8)
scheme_end = Str.to_utf8("://")

msg_prefix : List(U8)
msg_prefix = Str.to_utf8("MSG_")

a_open : List(U8)
a_open = Str.to_utf8("<a href=\"")

a_close : List(U8)
a_close = Str.to_utf8("</a>")

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
expect inline("[x](java\tscript:alert(1))") == "<a href=\"\">x</a>)"
expect inline("`a<b`") == "<code>a&lt;b</code>"
expect inline("go to www.a.com, now") == "go to <a href=\"http://www.a.com\" target=\"_blank\" rel=\"noopener\">www.a.com</a>, now"
expect inline("mail a.b@c.d.") == "mail <a href=\"mailto:a.b@c.d\">a.b@c.d</a>."
expect inline("http://localhost:9100/x.md") == "http://localhost:9100/x.md"
