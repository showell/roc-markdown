## **LINKS**: where a `[label](url)` link stands in a line, what its
## destination says (a src, a title, CommonMark's `<a b>`), and the `<a>` or
## `<img>` it becomes (its tags MdHtml's). Which hrefs are dangerous and which
## open in a new tab is MdSafety's; a dangerous link becomes no `<a>` at all,
## its source shown as text (MdInline). A link's label is the inline pass's
## (MdInline), which renders it as it renders a line. GFM's autolinks are
## MdAutolink's. Pure.
##
## **LINEAR BY ITS CURSORS**: the first `]` ahead (`next_bracket`) and the
## line's paren table (`Closes`) are each found once and only move forward,
## so no suffix is scanned again from every `[`. The pass holds them across
## its walk and passes them back in. Every byte a scan reads is charged to
## the budget.
import Bytes
import MdHtml
import MdText
import MdSafety

MdLinks := [].{

	## The link `[label](url)` at `at`: its
	## label's span, its destination, and the index past its `)`. In a chat a
	## label ends at the first `]`: `next_bracket`, the first `]` the line has not
	## yet passed, only moves forward, so its scans cost the line's length in all,
	## not once a `[`. In a document, where `brackets` is `Balanced`, it ends at
	## the `]` that balances its `[`, so a label may hold an image. The destination's parens
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
		brackets : LabelEnds,
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
		brackets : LabelEnds,
		closes : Closes,
		budget : MdText.Budget,
	}
	link_at = |text, { at, next_bracket, brackets, closes, budget }| {
		length = text.len()
		label = label_end(text, { at, next_bracket, brackets, budget })
		var $budget = label.budget
		paren_at = label.close + 1
		if label.close >= length or paren_at >= length or MdText.byte_at(text, paren_at) != '(' {
			{
				link: Err(NotALink),
				next_bracket: label.next_bracket,
				brackets: label.brackets,
				closes,
				budget: $budget,
			}
		} else {
			close_bracket = label.close
			open_paren = close_bracket + 1
			(table, scanned) = match closes {
				Scanned(scanned_table) => (scanned_table, $budget)
				Unscanned => (
					pair_closes(
						text,
						{
							opener: '(',
							closer: ')',
							escapes: Unread,
						},
					),
					MdText.charge($budget, length),
				)
			}
			$budget = scanned
			close_paren = table.get(open_paren) ?? length
			if close_paren >= length {
				{
					link: Err(NotALink),
					next_bracket: label.next_bracket,
					brackets: label.brackets,
					closes: Scanned(table),
					budget: $budget,
				}
			} else {
				{
					link: Ok({
						label: { start: at + 1, end: close_bracket },
						url: MdText.without_escapes(
							MdText.cut(text, { start: open_paren + 1, end: close_paren }),
						),
						end: close_paren + 1,
					}),
					next_bracket: label.next_bracket,
					brackets: label.brackets,
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

	## How a label's `]` is found: the first one, or the one that balances its
	## `[`, from a table `Closes` scans once, as it does for parens.
	LabelEnds : [FirstClose, Balanced(Closes)]

	## An image's destination, `src` or `src "title"` (CommonMark's link
	## destination and title, the title in `"…"`, `'…'` or `(…)`), its ends'
	## spaces dropped. Anything after the src that is no title is no image.
	## (A chat's link reads no title: it stays in the destination.)
	image_destination : List(U8) -> Try({ src : List(U8), title : MdHtml.Title }, [NotAnImage])
	image_destination = |url| {
		destination = MdText.trim_line(url)
		src_length = Bytes.count_while(
			destination,
			{ keep: |byte| byte != ' ' and byte != '\t', at: 0 },
		)
		titled_destination(destination.take_first(src_length), destination.drop_first(src_length))
	}

	## A document's destination, for its links and images alike: `image_destination`'s,
	## or CommonMark's `<a b>`, whose brackets let a src hold a space.
	document_destination : List(U8) -> Try({ src : List(U8), title : MdHtml.Title }, [NotAnImage])
	document_destination = |url| {
		destination = MdText.trim_line(url)
		close = Bytes.count_while(destination, { keep: |byte| byte != '<' and byte != '>', at: 1 })
		if destination.first() == Ok('<') and destination.get(close) == Ok('>') {
			titled_destination(
				MdText.cut(destination, { start: 1, end: close }),
				destination.drop_first(close + 1),
			)
		} else {
			image_destination(url)
		}
	}

	## `![alt](src "title")`'s tag: the one a member's `<img src alt title>`
	## is rebuilt as (MdSafety's allowlist), or `NotSafe` where its src is no
	## upload (`MdSafety.is_upload_url`, the rule `<img>` follows).
	image : {
		src : List(U8),
		alt : List(U8),
		title : MdHtml.Title,
		uploads : MdSafety.Uploads,
	} -> Try(List(U8), [NotSafe])
	image = |{ src, alt, title, uploads }| {
		attributes = MdSafety.media_attributes({
			kind: Img,
			uploads,
			value_of: |name|
				if name == "src".to_utf8() {
					Ok(src)
				} else if name == "alt".to_utf8() {
					Ok(alt)
				} else if name == "title".to_utf8() {
					match title {
						Titled(title_text) => Ok(title_text)
						Untitled => Err(Absent)
					}
				} else {
					Err(Absent)
				},
		})?
		Ok(MdHtml.img(attributes))
	}

	## A document's `![alt](src "title")`, the same tag `image` writes. The
	## uploads rule isn't asked, because a document's src is the host's own. A
	## dangerous src is still refused, so the sink stays safe whatever its
	## callers do.
	shown_image : {
		src : List(U8),
		alt : List(U8),
		title : MdHtml.Title,
	} -> Try(List(U8), [NotSafe])
	shown_image = |{ src, alt, title }|
		if MdSafety.is_dangerous_url(src) {
			Err(NotSafe)
		} else {
			named = [
				{ name: "src".to_utf8(), attribute_value: Is(src) },
				{ name: "alt".to_utf8(), attribute_value: Is(alt) },
			]
			Ok(
				MdHtml.img(
					match title {
						Titled(title_text) => named.append({
							name: "title".to_utf8(),
							attribute_value: Is(title_text),
						})
						Untitled => named
					},
				),
			)
		}

	## A `[label](url)` link's opening tag, `outside` saying how a link to
	## another site opens (MdSafety's rule). MdInline never asks it of a
	## dangerous url (such a link is shown as its source); the href is still
	## dropped here, so the sink stays safe whatever its callers do.
	link_open : List(U8), { outside : [SameTab, NewTab], title : MdHtml.Title } -> List(U8)
	link_open = |url, { outside, title }| MdHtml.link_open({
		href: if MdSafety.is_dangerous_url(url) {
			[]
		} else {
			url
		},
		tab: if MdSafety.is_external_href(url) {
			outside
		} else {
			SameTab
		},
		title,
	})
}

## Where the label `[` at `at` ends, or the text's length when it doesn't.
label_end : List(U8),
{
	at : U64,
	next_bracket : U64,
	brackets : MdLinks.LabelEnds,
	budget : MdText.Budget,
} -> {
	close : U64,
	next_bracket : U64,
	brackets : MdLinks.LabelEnds,
	budget : MdText.Budget,
}
label_end = |text, { at, next_bracket, brackets, budget }| {
	length = text.len()
	match brackets {
		FirstClose => {
			var $next_bracket = next_bracket
			var $budget = budget
			while $next_bracket < length and $next_bracket < at + 1 {
				from = $next_bracket
				$next_bracket = MdText.find_or_end(text, { byte: ']', at: $next_bracket + 1 })
				$budget = MdText.charge($budget, $next_bracket - from)
			}
			{
				close: $next_bracket,
				next_bracket: $next_bracket,
				brackets,
				budget: $budget,
			}
		}
		Balanced(Scanned(table)) => {
			close: table.get(at) ?? length,
			next_bracket,
			brackets,
			budget,
		}
		Balanced(Unscanned) => {
			table = pair_closes(
				text,
				{
					opener: '[',
					closer: ']',
					escapes: Read,
				},
			)
			{
				close: table.get(at) ?? length,
				next_bracket,
				brackets: Balanced(Scanned(table)),
				budget: MdText.charge(budget, length),
			}
		}
	}
}

## Each `opener`'s balancing `closer` in the line, by one pass of a stack: its
## index, or the line's length for an opener with none and every other byte.
## With `escapes` `Read`, a backslashed byte is neither.
pair_closes : List(U8),
{
	opener : U8,
	closer : U8,
	escapes : [Read, Unread],
} -> List(U64)
pair_closes = |text, { opener, closer, escapes }| {
	length = text.len()
	var $closes = List.repeat(length, length)
	var $open = []
	var $i = 0
	while $i < length {
		byte = MdText.byte_at(text, $i)
		if byte == '\\' and escapes == Read {
			$i = $i + 1
		} else if byte == opener {
			$open = $open.append($i)
		} else if byte == closer {
			match $open.last() {
				Ok(open_at) => {
					$closes = $closes.set(
						open_at,
						$i,
					) ?? crash "MdLinks.pair_closes: an opener past the line"
					$open = $open.drop_last(1)
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

## A destination's `src`, and what follows it read as a title. Anything else
## there is no destination.
titled_destination : List(U8),
List(U8) -> Try(
	{ src : List(U8), title : MdHtml.Title },
	[NotAnImage],
)
titled_destination = |src, after| {
	rest = MdText.trim_line(after)
	length = rest.len()
	if length == 0 {
		Ok({ src, title: Untitled })
	} else {
		first = MdText.byte_at(rest, 0)
		last = MdText.byte_at(rest, length - 1)
		quoted = (first == '"' and last == '"')
			or (first == '\'' and last == '\'')
			or (first == '(' and last == ')')
		if length >= 2 and quoted {
			Ok({ src, title: Titled(MdText.cut(rest, { start: 1, end: length - 1 })) })
		} else {
			Err(NotAnImage)
		}
	}
}
