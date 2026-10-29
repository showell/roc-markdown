## **WHAT A MEMBER'S LINK MAY BECOME** (chat-markdown markdown_inline.zig's
## `isDangerousUrl`, markdown_links.zig's `isExternalHref`): the one home of
## the inline pass's link rules, for an audit to read alone. A link whose
## destination a browser would run (`javascript:` and its kin) keeps its
## label but loses its href; a `scheme://` link opens in a new tab without
## the opener. The links themselves are found in MdLinks, which asks here.
##
## The dialect's other safety rules have their own homes: every byte a
## member wrote is escaped (MdText), and the one tag a member may write, a
## same-origin `<img>` or `<video>`, is rebuilt from an allowlist (MdMedia).
## Pure.
import Ascii
import Bytes
import MdText

MdSafety := [].{

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

	## markdown_links `isExternalHref`: a `scheme://…` href, which opens in a
	## new tab. `#msg-…`, `/chat/…` and `mailto:` are not.
	is_external_href : List(U8) -> Bool
	is_external_href = |href| match Bytes.find(href, { needle: MdSafety.scheme_end }) {
		Ok(p) =>
			p > 0 and Ascii.is_letter(MdText.at(href, 0)) and List.all(
				MdText.cut(href, { start: 1, end: p }),
				|c| Ascii.is_alphanumeric(c) or c == '+' or c == '.' or c == '-',
			)
		Err(NotFound) => Bool.False
	}

	## markdown_links `external_attrs`: a new tab, without the opener.
	external_attrs : List(U8)
	external_attrs = Str.to_utf8(" target=\"_blank\" rel=\"noopener\"")

	## The `://` that ends a URL's scheme: what makes a link external here,
	## and where an autolink's host starts (MdLinks).
	scheme_end : List(U8)
	scheme_end = Str.to_utf8("://")
}

dangerous_schemes : List(Str)
dangerous_schemes = [
	"javascript:",
	"vbscript:",
	"file:",
	"data:",
]

expect MdSafety.is_dangerous_url(Str.to_utf8("java\tscript:alert(1)"))
expect MdSafety.is_dangerous_url(Str.to_utf8("  JavaScript:x"))
expect MdSafety.is_dangerous_url(Str.to_utf8("data:text/html,x"))
expect !MdSafety.is_dangerous_url(Str.to_utf8("data:image/png;base64,x"))
expect !MdSafety.is_dangerous_url(Str.to_utf8("https://example.org"))
expect MdSafety.is_external_href(Str.to_utf8("https://example.org"))
expect !MdSafety.is_external_href(Str.to_utf8("#msg-plans_3"))
expect !MdSafety.is_external_href(Str.to_utf8("mailto:a@b.c"))
