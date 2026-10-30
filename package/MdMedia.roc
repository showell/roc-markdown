## **THE ONE PLACE THE DIALECT LETS A MEMBER'S TAG THROUGH**: an uploaded
## `<img>` or `<video>`. A tag a member wrote is never passed on as written:
## it is scanned here, its attributes by name, the last of a name winning,
## and REBUILT from MdSafety's allowlist (`media_attrs`, which also holds the
## uploads rule), each value escaped (MdHtml). A tag that does not parse cleanly, or that
## MdSafety refuses, is refused whole; the caller escapes it as text. Pure,
## over bytes: the renderer (Md, MdInline) asks it, and it is exposed, so a
## host that shows a stored tag outside a render (a feed of images) rebuilds
## it by the same rule (`rebuild`).
import MdHtml
import MdSafety
import MdText

MdMedia := [].{

	## A rebuilt tag, and the index past the source it stood for.
	Rebuilt : {
		html : List(U8),
		end : U64,
	}

	## The `<img …>` at `raw[start]` rebuilt,
	## and the index past its `>`.
	img_at : List(U8), U64, MdSafety.Uploads -> Try(Rebuilt, [NotSafe])
	img_at = |raw, start, uploads| {
		tag = scan(raw, { start, name: Str.to_utf8("img") })?
		attrs = MdSafety.media_attrs({ kind: Img, value_of: |name| last_of(tag.attrs, name), uploads })?
		Ok({ html: MdHtml.img(attrs), end: tag.end })
	}

	## The `<video …></video>` pair at
	## `raw[start]` rebuilt as a locked player, and the index past its
	## `</video>`. Only whitespace may stand between the two tags: no
	## fallback content is carried through.
	video_at : List(U8), U64, MdSafety.Uploads -> Try(Rebuilt, [NotSafe])
	video_at = |raw, start, uploads| {
		tag = scan(raw, { start, name: Str.to_utf8("video") })?
		attrs = MdSafety.media_attrs({ kind: Video, value_of: |name| last_of(tag.attrs, name), uploads })?
		close = close_tag_end(raw, { at: skip_spaces(raw, tag.end), name: Str.to_utf8("video") })?
		Ok({ html: MdHtml.video(attrs), end: close })
	}

	## The image tag `tag` (`<img …>`, from its `<`) rebuilt, or `Unsafe`:
	## the Images feed's door, `img_at` at the tag's start.
	rebuild : Str, MdSafety.Uploads -> Try(Str, [Unsafe])
	rebuild = |tag, uploads| match img_at(Str.to_utf8(tag), 0, uploads) {
		Ok(rebuilt) =>
			match Str.from_utf8(rebuilt.html) {
				Ok(text) => Ok(text)
				Err(_) => crash "MdMedia.rebuild: a tag cut from text at ASCII bytes is text"
			}
		Err(NotSafe) => Err(Unsafe)
	}
}

## A start tag's attributes, each name as written, and the index past its
## `>`.
Tag : {
	attrs : List((List(U8), List(U8))),
	end : U64,
}

## `<name` (any case) at `start`,
## then a space, `>` or `/`; then each `name=value` up to the tag's `>`,
## quotes respected, a bare name's value empty. Running off the end, a name
## of no name bytes, or `=` with nothing after is no tag.
scan : List(U8), { start : U64, name : List(U8) } -> Try(Tag, [NotSafe])
scan = |raw, { start, name }| {
	after = start + 1 + List.len(name)
	if after >= List.len(raw) or MdText.at(raw, start) != '<' or !MdText.is_same_ignoring_case(
		MdText.cut(raw, { start: start + 1, end: after }),
		name,
	) {
		Err(NotSafe)
	} else {
		d = MdText.at(raw, after)
		if !MdText.is_space(d) and d != '>' and d != '/' {
			Err(NotSafe)
		} else {
			attrs_from(raw, after)
		}
	}
}

## TagScan's walk from `i`, just past the tag's name.
attrs_from : List(U8), U64 -> Try(Tag, [NotSafe])
attrs_from = |raw, from| {
	len = List.len(raw)
	var $i = from
	var $attrs = []
	var $end = 0
	while $i < len and $end == 0 {
		c = MdText.at(raw, $i)
		if MdText.is_space(c) or c == '/' {
			$i = $i + 1
		} else if c == '>' {
			$end = $i + 1
		} else {
			name_start = $i
			while $i < len and MdText.is_attr_name_char(MdText.at(raw, $i)) {
				$i = $i + 1
			}
			if $i == name_start {
				return Err(NotSafe)
			} else {
				{}
			}
			name = MdText.cut(raw, { start: name_start, end: $i })
			$i = skip_spaces(raw, $i)
			if $i < len and MdText.at(raw, $i) == '=' {
				$i = skip_spaces(raw, $i + 1)
				if $i >= len {
					return Err(NotSafe)
				} else {
					{}
				}
				q = MdText.at(raw, $i)
				if q == '"' or q == '\'' {
					value_start = $i + 1
					close = MdText.find_or_end(raw, { byte: q, at: value_start })
					if close >= len {
						return Err(NotSafe)
					} else {
						{}
					}
					$attrs = List.append(
						$attrs,
						(name, MdText.cut(raw, { start: value_start, end: close })),
					)
					$i = close + 1
				} else {
					value_start = $i
					while $i < len and !MdText.is_space(
						MdText.at(
							raw,
							$i,
						),
					) and MdText.at(raw, $i) != '>' {
						$i = $i + 1
					}
					$attrs = List.append(
						$attrs,
						(name, MdText.cut(raw, { start: value_start, end: $i })),
					)
				}
			} else {
				$attrs = List.append($attrs, (name, []))
			}
		}
	}
	# A tag ends past its `>`, never at 0: 0 is a walk that ran off the end.
	if $end == 0 Err(NotSafe) else Ok({ attrs: $attrs, end: $end })
}

skip_spaces : List(U8), U64 -> U64
skip_spaces = |raw, from| {
	var $i = from
	while $i < List.len(raw) and MdText.is_space(MdText.at(raw, $i)) {
		$i = $i + 1
	}
	$i
}

## `</name>` at `at` (any case, spaces
## before the `>`), and the index past it.
close_tag_end : List(U8), { at : U64, name : List(U8) } -> Try(U64, [NotSafe])
close_tag_end = |raw, { at, name }| {
	n = List.len(name)
	if at + 2 + n > List.len(raw) or MdText.at(raw, at) != '<' or MdText.at(raw, at + 1) != '/' {
		Err(NotSafe)
	} else if !MdText.is_same_ignoring_case(
		MdText.cut(raw, { start: at + 2, end: at + 2 + n }),
		name,
	) {
		Err(NotSafe)
	} else {
		i = skip_spaces(raw, at + 2 + n)
		if i >= List.len(raw) or MdText.at(raw, i) != '>' Err(NotSafe) else Ok(i + 1)
	}
}

## The last value of attribute `name` (lowercase), in any case.
last_of : List((List(U8), List(U8))), List(U8) -> Try(List(U8), [Absent])
last_of = |attrs, name| match List.find_last(
	attrs,
	|(n, _)| MdText.is_same_ignoring_case(n, name),
) {
	Ok((_, v)) => Ok(v)
	Err(NotFound) => Err(Absent)
}

# markdown_media's cases, each as its test has it, under a host whose uploads
# are `/user_uploads/`.
user_uploads : MdSafety.Uploads
user_uploads = MdSafety.under(Str.to_utf8("/user_uploads/"))

img : Str -> Str
img = |raw| match MdMedia.img_at(Str.to_utf8(raw), 0, user_uploads) {
	Ok(r) => Str.from_utf8(r.html) ?? "not text"
	Err(NotSafe) => ""
}

video : Str -> Str
video = |raw| match MdMedia.video_at(Str.to_utf8(raw), 0, user_uploads) {
	Ok(r) => Str.from_utf8(r.html) ?? "not text"
	Err(NotSafe) => ""
}

expect img("<img src=\"/user_uploads/cat.png\" alt=\"a cat\" width=\"200\" onerror=\"x()\" style=\"z\">") == "<img src=\"/user_uploads/cat.png\" alt=\"a cat\" width=\"200\">"
expect img("<img src=\"/user_uploads/x.png\" width=\"320\" height=\"240\">") == "<img src=\"/user_uploads/x.png\" width=\"320\" height=\"240\">"
expect img("<img src=\"/user_uploads/x.png\" width=\"100%\" height=\"auto\">") == "<img src=\"/user_uploads/x.png\">"
expect img("<img src=\"https://evil/x.png\">") == ""
expect img("<img src=\"//evil/x.png\">") == ""
expect img("<img src=\"/\\evil\">") == ""
expect img("<img alt=\"no src\">") == ""
expect video("<video src=\"/user_uploads/clip.mp4\" width=\"640\" onerror=\"x()\"></video>") == "<video controls preload=\"metadata\" src=\"/user_uploads/clip.mp4\" width=\"640\"></video>"
expect video("<video src=\"https://evil/x.mp4\"></video>") == ""
expect video("<video src=\"/user_uploads/x.mp4\">") == ""
expect img("<img src=\"/\t/evil.example/x.png\">") == ""
expect img("<img src=\"/\n/evil.example/x.png\">") == ""
expect img("<img src=\"/\r\n/evil.example/x.png\">") == ""
expect img("<img src=\"/user_uploads/\\\\evil.example/x.png\">") == ""
expect video("<video src=\"/\t/evil.example/x.mp4\"></video>") == ""
expect img("<img src=\" /user_uploads/cat.png \">") == "<img src=\" /user_uploads/cat.png \">"
# The host's rule decides: none renders no media, and its own path is the
# only one it lets through.
expect MdMedia.img_at(Str.to_utf8("<img src=\"/user_uploads/x.png\">"), 0, |_| Bool.False) == Err(NotSafe)
expect MdMedia.img_at(Str.to_utf8("<img src=\"/files/x.png\">"), 0, MdSafety.under(Str.to_utf8("/files/"))).is_ok()
# The Images feed's (SafeImg's, folded here): its plants, escaped values,
# case-blind names, the last of a name winning, single quotes, a bare name.
expect MdMedia.rebuild("<img src=x onerror=\"alert(1)\">", user_uploads) == Err(Unsafe)
expect MdMedia.rebuild("<img src=\"/user_uploads/a.png\" width=\"40\" onload=\"alert(2)\">", user_uploads) == Ok("<img src=\"/user_uploads/a.png\" width=\"40\">")
expect MdMedia.rebuild("<IMG SRC='/user_uploads/a.png' alt=\"x\" ALT=y&z hidden>", user_uploads) == Ok("<img src=\"/user_uploads/a.png\" alt=\"y&amp;z\">")
expect MdMedia.rebuild("<img src=\"/user_uploads/a.png\" alt=\"<b>\">", user_uploads) == Ok("<img src=\"/user_uploads/a.png\" alt=\"&lt;b&gt;\">")
expect MdMedia.rebuild("<img src=\"/user_uploads/a.png\"", user_uploads) == Err(Unsafe)
expect MdMedia.rebuild("<img src=\"/a.png>", user_uploads) == Err(Unsafe)
expect MdMedia.rebuild("<img src=", user_uploads) == Err(Unsafe)
expect MdMedia.video_at(Str.to_utf8("x<VIDEO src=/user_uploads/v.mp4 >  </Video >y"), 1, user_uploads) == Ok({
	html: Str.to_utf8("<video controls preload=\"metadata\" src=\"/user_uploads/v.mp4\"></video>"),
	end: 44,
})
