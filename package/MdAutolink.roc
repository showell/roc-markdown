## **GFM'S AUTOLINKS, AND A DOCUMENT'S `<http://…>`**: where a bare
## `http://…`, `https://…`, `www.…` or `local@domain.tld` stands in a line,
## or a URL in angle brackets, and the `<a>` each becomes (its tags MdHtml's).
## How a link to another site opens is the caller's `outside` (MdSafety's
## rule). A `[label](url)` link is MdLinks'. Pure.
##
## **LINEAR BY ITS FLOOR**: `email_dead`, the floor below which no email can
## start, is found as the walk goes and only moves forward, so no suffix is
## scanned again from every `_`. The inline pass (MdInline) holds it across
## its walk and passes it back in. Every byte a scan reads is charged to the
## budget.
import Ascii
import Bytes
import MdHtml
import MdText
import MdSafety

MdAutolink := [].{

	## `<http://…>` or `<https://…>` at `at`: its URL, and the index past its
	## `>`. The brackets say where it starts and ends, so no boundary rule or
	## host rule applies, and `localhost` is a host here. A space or a control
	## byte inside makes it text, as does nothing after the `://`.
	angle_url_at : List(U8), U64 -> Try({ url : List(U8), end : U64 }, [NotALink])
	angle_url_at = |text, at| {
		start = at + 1
		is_prefixed = |prefix| MdText.is_prefixed_ignoring_case(
			text,
			{ at: start, prefix: prefix.to_utf8() },
		)
		scheme_len = if is_prefixed("http://") {
			7
		} else if is_prefixed("https://") {
			8
		} else {
			0
		}
		close = Bytes.count_while(
			text,
			{ keep: |c| c > ' ' and c != 0x7f and c != '<' and c != '>', at: start },
		)
		if scheme_len == 0 or close <= start + scheme_len or text.get(close) != Ok('>') {
			Err(NotALink)
		} else {
			Ok({ url: MdText.cut(text, { start, end: close }), end: close + 1 })
		}
	}

	## The line is one angle-bracket URL and nothing else, which the dispatcher
	## would otherwise take for an HTML tag.
	is_angle_url_line : List(U8) -> Bool
	is_angle_url_line = |line| {
		t = MdText.trim_line(line)
		match angle_url_at(t, 0) {
			Ok(found) => found.end == t.len()
			Err(NotALink) => Bool.False
		}
	}

	## An autolink starts only at the line's
	## start, or after a space or one of `*`, `_`, `~` and `(`.
	is_autolink_boundary : List(U8), U64 -> Bool
	is_autolink_boundary = |text, i|
		if i == 0 {
			Bool.True
		} else {
			p = MdText.byte_at(text, i - 1)
			MdText.is_space(p) or p == '*' or p == '_' or p == '~' or p == '('
		}

	AutoKind : [Url, Www, Email]

	## A GFM autolink at `at`, and the index past
	## it. `email_dead` is the floor below which no email can start: when one
	## fails, every position in its local part fails the same way, so the floor
	## moves past it (without it, `a_b_a_b…` is quadratic). `Plain` emails stay
	## text, for a document whose `a@b.c` is rarely an address.
	autolink_at : List(U8),
	{
		at : U64,
		email_dead : U64,
		emails : [Linked, Plain],
		budget : MdText.Budget,
	} -> {
		link : Try({ end : U64, kind : AutoKind }, [NotALink]),
		email_dead : U64,
		budget : MdText.Budget,
	}
	autolink_at = |text, { at, email_dead, emails, budget }| {
		starts_with = |prefix| MdText.is_prefixed_ignoring_case(
			text,
			{ at, prefix: prefix.to_utf8() },
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
		} else if emails == Linked and at >= email_dead {
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
						email_dead: if j > at {
							j
						} else {
							at + 1
						},
						budget: MdText.charge(e.budget, j - at),
					}
				}
			}
		} else {
			{ link: Err(NotALink), email_dead, budget }
		}
	}

	## The link, a URL's and a `www.`'s opening
	## as `outside` says, an email's as `mailto:`.
	autolink_html : List(U8), { kind : AutoKind, outside : [SameTab, NewTab] } -> List(U8)
	autolink_html = |link, { kind, outside }| {
		head = match kind {
			Url => MdHtml.link_open({
				href: link,
				tab: outside,
				title: Untitled,
			})
			Www => MdHtml.link_open({
				href: List.concat("http://".to_utf8(), link),
				tab: outside,
				title: Untitled,
			})
			Email => MdHtml.link_open({
				href: List.concat("mailto:".to_utf8(), link),
				tab: SameTab,
				title: Untitled,
			})
		}
		List.concat(MdText.escape_onto(head, link), MdHtml.link_close)
	}
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
	if !MdText.cut(url, { start: host_start, end: U64.max(host_start, host_end) }).contains('.') {
		{ end: Err(NotALink), budget: spent }
	} else {
		opens = url.count_if(|c| c == '(')
		var $closes = url.count_if(|c| c == ')')
		var $end = scanned
		while $end > start {
			c = MdText.byte_at(text, $end - 1)
			if trailing_punct.contains(c) {
				$end = $end - 1
			} else if c == ')' and $closes > opens {
				$end = $end - 1
				$closes = $closes - 1
			} else {
				break
			}
		}
		{
			end: if $end <= start + 4 {
				Err(NotALink)
			} else {
				Ok($end)
			},
			budget: spent,
		}
	}
}

## `local@domain.tld` at `start`, a trailing `.` not its. A domain that then
## ends in `-` or `_` is no address at all (GFM's).
email_end : List(U8),
{ start : U64, budget : MdText.Budget } -> {
	end : Try(U64, [NotALink]),
	budget : MdText.Budget,
}
email_end = |text, { start, budget }| {
	local_end = Bytes.count_while(text, { keep: is_email_local_char, at: start })
	local_spent = MdText.charge(budget, local_end - start)
	if local_end == start or local_end >= text.len() or MdText.byte_at(text, local_end) != '@' {
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
		if domain_end == domain_start or !MdText.cut(
			text,
			{ start: domain_start, end: domain_end },
		).contains('.') {
			{ end: Err(NotALink), budget: spent }
		} else {
			var $j = domain_end
			while $j > domain_start and MdText.byte_at(text, $j - 1) == '.' {
				$j = $j - 1
			}
			ends_badly = $j == domain_start or ['-', '_'].contains(MdText.byte_at(text, $j - 1))
			{
				end: if ends_badly {
					Err(NotALink)
				} else {
					Ok($j)
				},
				budget: spent,
			}
		}
	}
}

is_email_local_char : U8 -> Bool
is_email_local_char = |c| Ascii.is_alphanumeric(c) or c == '.' or c == '_' or c == '+' or c == '-'

trailing_punct : List(U8)
trailing_punct = "?!.,:*_~'\"".to_utf8()

# A trailing `.` is the sentence's; a domain ending in `-` or `_` is no address.
expect email_end("a@b.c".to_utf8(), { start: 0, budget: MdText.unlimited }).end == Ok(5)
expect email_end("a@b.c.".to_utf8(), { start: 0, budget: MdText.unlimited }).end == Ok(5)
expect email_end("a@b.c-".to_utf8(), { start: 0, budget: MdText.unlimited }).end == Err(NotALink)
expect email_end("a@b.c_.".to_utf8(), { start: 0, budget: MdText.unlimited }).end == Err(NotALink)
expect email_end("a@b-c.d".to_utf8(), { start: 0, budget: MdText.unlimited }).end == Ok(7)
