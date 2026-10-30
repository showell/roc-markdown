## **LINKS AND AUTOLINKS**: where a `[label](url)` link or a GFM
## autolink (`http://…`, `https://…`, `www.…`, `local@domain.tld`) stands in
## a line, and the `<a>` each becomes (its tags MdHtml's). Which hrefs are
## dangerous and which open in a new tab is MdSafety's; a link's label is the inline pass's
## (MdInline), which renders it as it renders a line. Pure.
##
## **LINEAR BY ITS CURSORS**: the first `]` ahead (`next_bracket`), the line's paren
## table (`Closes`), and the floor below which no email can start
## (`email_dead`) are each found once and only move forward, so no suffix is
## scanned again from every `[` or every `_`. The pass holds them across its
## walk and passes them back in. Every byte a scan reads is charged to the
## budget.
import Ascii
import Bytes
import MdHtml
import MdText
import MdSafety

MdLinks := [].{

	## The link `[label](url)` at `at`: its
	## label's span, its destination, and the index past its `)`. `next_bracket`, the
	## first `]` the line has not yet passed, only moves forward, so its scans
	## cost the line's length in all, not once a `[`. The destination's parens
	## balance (CommonMark): it ends at the `)` that closes its `(`, from
	## `closes`, the line's one paren pass, made at the first `](` and charged
	## its length once. A `(` with no balancing `)` is no link. The
	## destination's backslash escapes are taken out (CommonMark's
	## `/bar\*` is `/bar*`) before MdSafety reads it, so `javascript\:` is
	## as dangerous as `javascript:`; a `\)` still closes (the paren pass
	## reads no escapes).
	link_at : List(U8),
	{
		at : U64,
		next_bracket : U64,
		closes : Closes,
		budget : MdText.Budget,
	} -> {
		link : Try(
			{
				label : { start : U64, end : U64 },
				url : List(U8),
				end : U64,
			},
			[NotALink],
		),
		next_bracket : U64,
		closes : Closes,
		budget : MdText.Budget,
	}
	link_at = |
		text,
		{
			at,
			next_bracket,
			closes,
			budget,
		},
	| {
		len = List.len(text)
		var $next_bracket = next_bracket
		var $budget = budget
		while $next_bracket < len and $next_bracket < at + 1 {
			from = $next_bracket
			$next_bracket = MdText.find_or_end(text, { byte: ']', at: $next_bracket + 1 })
			$budget = MdText.charge($budget, $next_bracket - from)
		}
		if $next_bracket >= len or $next_bracket + 1 >= len or MdText.at(text, $next_bracket + 1) != '(' {
			{
				link: Err(NotALink),
				next_bracket: $next_bracket,
				closes,
				budget: $budget,
			}
		} else {
			close_bracket = $next_bracket
			open_paren = close_bracket + 1
			(table, scanned) = match closes {
				Scanned(t) => (t, $budget)
				Unscanned => (paren_closes(text), MdText.charge($budget, len))
			}
			$budget = scanned
			close_paren = List.get(table, open_paren) ?? len
			if close_paren >= len {
				{
					link: Err(NotALink),
					next_bracket: $next_bracket,
					closes: Scanned(table),
					budget: $budget,
				}
			} else {
				{
					link: Ok({
						label: { start: at + 1, end: close_bracket },
						url: MdText.unescaped(MdText.cut(text, { start: open_paren + 1, end: close_paren })),
						end: close_paren + 1,
					}),
					next_bracket: $next_bracket,
					closes: Scanned(table),
					budget: $budget,
				}
			}
		}
	}

	## Each `(`'s balancing `)` in the line, found once, by a stack: the index
	## of the `)` that closes the `(` at `i`, or the line's length when none
	## does (and for every byte that is no `(`). One pass, so a line of
	## `[a](((…` costs its length once, not once a `](`.
	Closes : [Unscanned, Scanned(List(U64))]

	## An image's destination, `src` or `src "title"` (CommonMark's link
	## destination and title, the title in `"…"`, `'…'` or `(…)`), its ends'
	## spaces dropped. Anything after the src that is no title is no image.
	## (A link's title is not read: it stays in the destination.)
	image_dest : List(U8) -> Try({ src : List(U8), title : [None, Some(List(U8))] }, [NotAnImage])
	image_dest = |url| {
		dest = MdText.trim_line(url)
		src_len = Bytes.count_while(dest, { keep: |c| c != ' ' and c != '\t', at: 0 })
		src = List.take_first(dest, src_len)
		rest = MdText.trim_line(List.drop_first(dest, src_len))
		n = List.len(rest)
		if n == 0 {
			Ok({ src, title: None })
		} else {
			first = MdText.at(rest, 0)
			last = MdText.at(rest, n - 1)
			quoted = (first == '"' and last == '"') or (first == '\'' and last == '\'') or (first == '(' and last == ')')
			if n >= 2 and quoted {
				Ok({ src, title: Some(MdText.cut(rest, { start: 1, end: n - 1 })) })
			} else {
				Err(NotAnImage)
			}
		}
	}

	## `![alt](src "title")`'s tag: the one a member's `<img src alt title>`
	## is rebuilt as (MdSafety's allowlist), or `NotSafe` where its src is no
	## upload (`MdSafety.is_upload_url`, the rule `<img>` follows).
	image : { src : List(U8), alt : List(U8), title : [None, Some(List(U8))], uploads : MdSafety.Uploads } -> Try(List(U8), [NotSafe])
	image = |{ src, alt, title, uploads }| {
		attrs = MdSafety.media_attrs({
			kind: Img,
			uploads,
			value_of: |name|
				if name == Str.to_utf8("src") {
					Ok(src)
				} else if name == Str.to_utf8("alt") {
					Ok(alt)
				} else if name == Str.to_utf8("title") {
					match title {
						Some(t) => Ok(t)
						None => Err(Absent)
					}
				} else {
					Err(Absent)
				},
		})?
		Ok(MdHtml.img(attrs))
	}

	## A `[label](url)` link's opening tag: its href dropped when dangerous,
	## and a new tab when external (MdSafety's rules both).
	link_open : List(U8) -> List(U8)
	link_open = |url| MdHtml.link_open({
		href: if MdSafety.is_dangerous_url(url) [] else url,
		tab: if MdSafety.is_external_href(url) NewTab else SameTab,
	})

	## An autolink starts only at the line's
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

	## A GFM autolink at `at`, and the index past
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

	## The link, a URL's and a `www.`'s opening
	## in a new tab, an email's as `mailto:`.
	autolink_html : List(U8), AutoKind -> List(U8)
	autolink_html = |link, kind| {
		head = match kind {
			Url => MdHtml.link_open({ href: link, tab: NewTab })
			Www => MdHtml.link_open({ href: List.concat(Str.to_utf8("http://"), link), tab: NewTab })
			Email => MdHtml.link_open({ href: List.concat(Str.to_utf8("mailto:"), link), tab: SameTab })
		}
		List.concat(MdText.escape_onto(head, link), MdHtml.link_close)
	}
}

paren_closes : List(U8) -> List(U64)
paren_closes = |text| {
	len = List.len(text)
	var $closes = List.repeat(len, len)
	var $open = []
	var $i = 0
	while $i < len {
		c = MdText.at(text, $i)
		if c == '(' {
			$open = List.append($open, $i)
		} else if c == ')' {
			match List.last($open) {
				Ok(j) => {
					$closes = List.set($closes, j, $i) ?? crash "MdLinks.paren_closes: a ( past the line"
					$open = List.drop_last($open, 1)
				}
				Err(ListWasEmpty) => {}
			}
		} else {
			{}
		}
		$i = $i + 1
	}
	$closes
}

## URL bytes from `start` up to a space or `<`,
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
	host_start = match Bytes.find(url, { needle: MdSafety.scheme_end }) {
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

## `local@domain.tld` at `start`, a trailing
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

trailing_punct : List(U8)
trailing_punct = Str.to_utf8("?!.,:*_~'\"")
