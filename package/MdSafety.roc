## **WHAT A MEMBER'S LINK OR MEDIA MAY BECOME**: the one home of the renderer's URL and attribute rules, for an audit to read
## alone.
##   - **Links** (MdLinks finds them and asks here): one whose destination a
##     browser would run (`javascript:` and its kin) keeps its label but
##     loses its href; a `scheme://` link opens in a new tab without the
##     opener.
##   - **Media** (MdMedia scans a member's `<img>` or `<video>` and asks
##     here): the tag is rebuilt from an allowlist, and only when its src is
##     a same-origin URL that the host's rule calls one of its uploads (the
##     render's options, `Uploads`). Anything else
##     (onerror=, onload=, style=, an off-site or protocol-relative src, any
##     other path of the app's own) is dropped.
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

	## `javascript:`, `vbscript:`, `file:`,
	## and `data:` but for an image's, **READ AS A BROWSER READS IT**: its ends' control bytes and spaces dropped, and every tab
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

	## A `scheme://…` href, which opens in a
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
	## value of a name; `NotSafe` when its src is no upload
	## (`is_upload_url`). An image keeps its src, alt and title; a video its
	## src, and is a player: `controls` and `preload="metadata"`, never
	## autoplay. Both keep width and height when all digits, which the page
	## needs to hold the media's place while it loads.
	media_attrs : {
		kind : [Img, Video],
		value_of : List(U8) -> Try(List(U8), [Absent]),
		uploads : MdSafety.Uploads,
	} -> Try(List(MdHtml.Attr), [NotSafe])
	media_attrs = |{ kind, value_of, uploads }| {
		src = match value_of(Str.to_utf8("src")) {
			Ok(v) => v
			Err(Absent) => return Err(NotSafe)
		}
		if !MdSafety.is_upload_url(Bytes.trim(src, Bytes.zig_spaces), uploads) {
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

	## **WHICH SAME-ORIGIN PATHS ARE THE HOST'S UPLOADS**: the host's rule,
	## asked of a path this module has already judged safe as a URL. Where a
	## host keeps its files is the host's to say, never the renderer's; a
	## rule that says no to every path (`Md.no_uploads`) renders no media.
	Uploads : List(U8) -> Bool

	## **AN UPLOAD, AND ONLY AN UPLOAD**: a path the host's rule calls one
	## of its uploads (`uploads`), and a same-origin URL as a browser reads
	## it:
	##   - a path from this site's root: one `/`, never `//` (another site);
	##   - no control byte and no backslash anywhere: a browser strips tabs
	##     and newlines inside a URL and reads `\` as `/`, so `/\t/evil` is
	##     `//evil`;
	##   - no `..` segment, however spelled: a browser resolves `..`, `.%2e`,
	##     `%2e.` and `%2e%2e` (either case) alike before it asks, so
	##     `/user_uploads/../login` is `/login`;
	##   - no `%2f` or `%5c`: an encoded `/` or `\` a server may decode into
	##     a separator. Every other escape stays: an upload's name may need one.
	##
	## The rule is asked last, so no rule a host writes can let through a
	## path the URL's own checks refuse.
	is_upload_url : List(U8), MdSafety.Uploads -> Bool
	is_upload_url = |src, uploads|
		List.starts_with(src, ['/'])
			and !List.starts_with(src, ['/', '/'])
				and List.all(src, |c| c >= 0x20 and c != 0x7f and c != '\\')
					and !has_dot_dot_segment(src)
						and !has_encoded_separator(src)
							and uploads(src)

	## **THE RULE OF ONE UPLOADS FOLDER**: a path under `prefix`
	## (`/user_uploads/`), the shape most hosts need.
	under : List(U8) -> MdSafety.Uploads
	under = |prefix| |path| List.starts_with(path, prefix)

	## The `://` that ends a URL's scheme: what makes a link external here,
	## and where an autolink's host starts (MdLinks).
	scheme_end : List(U8)
	scheme_end = Str.to_utf8("://")
}

## `%2e` (either case) read as the `.` a browser takes it for.
dots_decoded : List(U8) -> List(U8)
dots_decoded = |src| {
	len = List.len(src)
	var $out = []
	var $i = 0
	while $i < len {
		if is_escape_of(src, { at: $i, hex: ['2', 'e'] }) {
			$out = List.append($out, '.')
			$i = $i + 3
		} else {
			$out = List.append($out, MdText.at(src, $i))
			$i = $i + 1
		}
	}
	$out
}

## Whether `src` holds `%` and the two hex digits `hex` (lowercase) at `at`,
## either case.
is_escape_of : List(U8), { at : U64, hex : List(U8) } -> Bool
is_escape_of = |src, { at, hex }|
	List.get(src, at) == Ok('%')
		and List.map(List.sublist(src, { start: at + 1, len: 2 }), Ascii.to_lowercase) == hex

## A `..` path segment, its dots written or encoded.
has_dot_dot_segment : List(U8) -> Bool
has_dot_dot_segment = |src| List.any(List.split_on(dots_decoded(src), '/'), |segment| segment == ['.', '.'])

## An encoded `/` or `\`.
has_encoded_separator : List(U8) -> Bool
has_encoded_separator = |src| {
	var $i = 0
	var $found = Bool.False
	while $i < List.len(src) and !$found {
		$found = is_escape_of(src, { at: $i, hex: ['2', 'f'] }) or is_escape_of(src, { at: $i, hex: ['5', 'c'] })
		$i = $i + 1
	}
	$found
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
expect MdSafety.is_upload_url(Str.to_utf8("/user_uploads/a.png"), user_uploads)
expect MdSafety.is_upload_url(Str.to_utf8("/user_uploads/1/caf%C3%A9 a.png"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/conversations/1/stream"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/login"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/../login"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/%2e%2E/login"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/.%2e/login"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/a/.."), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/..%2flogin"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/%5c..%5clogin"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploadsX/a.png"), user_uploads)
expect !MdSafety.is_upload_url(Str.to_utf8("//user_uploads/a.png"), user_uploads)
expect MdSafety.is_upload_url(Str.to_utf8("/user_uploads/a..b.png"), user_uploads)
expect MdSafety.is_dangerous_url(Str.to_utf8("  JavaScript:x"))
expect MdSafety.is_dangerous_url(Str.to_utf8("data:text/html,x"))
expect !MdSafety.is_dangerous_url(Str.to_utf8("data:image/png;base64,x"))
expect !MdSafety.is_dangerous_url(Str.to_utf8("https://example.org"))
expect MdSafety.is_external_href(Str.to_utf8("https://example.org"))
expect !MdSafety.is_external_href(Str.to_utf8("#msg-plans_3"))
expect !MdSafety.is_external_href(Str.to_utf8("mailto:a@b.c"))

user_uploads : MdSafety.Uploads
user_uploads = MdSafety.under(Str.to_utf8("/user_uploads/"))

# The host's rule is asked only of a path the URL's checks let through: a
# rule that takes every path still refuses another site and a `..`.
anything : MdSafety.Uploads
anything = |_| Bool.True

expect MdSafety.is_upload_url(Str.to_utf8("/u/cat.png"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("//evil/x.png"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("/\\evil"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("https://evil/x.png"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("/u/../login"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("x.png"), anything)
expect !MdSafety.is_upload_url(Str.to_utf8("/user_uploads/a.png"), |_| Bool.False)
