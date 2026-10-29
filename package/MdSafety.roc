## **WHAT A MEMBER'S LINK OR MEDIA MAY BECOME** (chat-markdown
## markdown_inline.zig's `isDangerousUrl`, markdown_links.zig's
## `isExternalHref`, markdown_media.zig's `isLocalUrl` and allowlist): the
## one home of the renderer's URL and attribute rules, for an audit to read
## alone.
##   - **Links** (MdLinks finds them and asks here): one whose destination a
##     browser would run (`javascript:` and its kin) keeps its label but
##     loses its href; a `scheme://` link opens in a new tab without the
##     opener.
##   - **Media** (MdMedia scans a member's `<img>` or `<video>` and asks
##     here): the tag is rebuilt from an allowlist, and only when its src is
##     same-origin and root-relative. Anything else (onerror=, onload=,
##     style=, an off-site or protocol-relative src) is dropped.
##   - **Markdown's images** (`![alt](src "title")`, MdInline and MdLinks)
##     follow the media's rule exactly: a same-origin src is the very
##     `<img src alt title>` a member's tag of that src and alt is rebuilt
##     as. **ANY OTHER SRC IS A LINK, THE `!` DROPPED**: the label its text,
##     under the link rules above (a `javascript:` src keeps no href, another
##     site's opens a new tab). Not the text as written, because the link
##     still says where the image is and lets a reader choose to open it,
##     while the page fetches nothing from another site (no tracking pixel,
##     no hotlink); and the markup as written would be noise.
##
## The other safety rule has its own home: every byte a member wrote is
## escaped (MdText). Pure.
import Ascii
import Bytes
import MdHtml
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

	## markdown_media's allowlist: the attributes a member's `<img>` or
	## `<video>` is rebuilt with, in order, `value_of` giving the tag's last
	## value of a name; `NotSafe` when its src is no same-origin path
	## (`is_local_url`). An image keeps its src, alt and title; a video its
	## src, and is a player: `controls` and `preload="metadata"`, never
	## autoplay. Both keep width and height when all digits, which the page
	## needs to hold the media's place while it loads.
	media_attrs : {
		kind : [Img, Video],
		value_of : List(U8) -> Try(List(U8), [Absent]),
	} -> Try(List(MdHtml.Attr), [NotSafe])
	media_attrs = |{ kind, value_of }| {
		src = match value_of(Str.to_utf8("src")) {
			Ok(v) => v
			Err(Absent) => return Err(NotSafe)
		}
		if !MdSafety.is_local_url(Bytes.trim(src, Bytes.zig_spaces)) {
			Err(NotSafe)
		} else {
			kept = |names, keep| List.join_map(
				names,
				|name| match value_of(name) {
					Ok(v) if keep(v) => [{ name, value: Is(v) }]
					_ => []
				},
			)
			player = if kind == Video video_player else []
			texts = if kind == Img kept([Str.to_utf8("alt"), Str.to_utf8("title")], |_| Bool.True) else []
			# The src as written, its ends' spaces kept.
			Ok(
				List.join([
					player,
					[{ name: Str.to_utf8("src"), value: Is(src) }],
					texts,
					kept([Str.to_utf8("width"), Str.to_utf8("height")], MdText.is_all_digits),
				]),
			)
		}
	}

	## markdown_media `isLocalUrl`: `/` then anything but `/` or `\`, and no
	## control byte or backslash anywhere: a browser strips tabs and newlines
	## inside a URL and reads `\` as `/`, so `/\t/evil` is `//evil` (metal-vmm
	## QUEUE 172).
	is_local_url : List(U8) -> Bool
	is_local_url = |src|
		match src {
			[
				'/',
				second,
				..,
			] if second != '/' and second != '\\' => List.all(
				src,
				|c| c >= 0x20 and c != 0x7f and c != '\\',
			)
			_ => Bool.False
		}

	## The `://` that ends a URL's scheme: what makes a link external here,
	## and where an autolink's host starts (MdLinks).
	scheme_end : List(U8)
	scheme_end = Str.to_utf8("://")
}

## A video is a player the reader starts: never autoplay.
video_player : List(MdHtml.Attr)
video_player = [
	{ name: Str.to_utf8("controls"), value: Bare },
	{ name: Str.to_utf8("preload"), value: Is(Str.to_utf8("metadata")) },
]

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
