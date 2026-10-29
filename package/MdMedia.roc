## **THE ONE PLACE THE DIALECT LETS A MEMBER'S TAG THROUGH** (chat-markdown
## markdown_media.zig): a same-origin `<img>` or `<video>`. A tag a member
## wrote is never passed on as written: it is REBUILT from a fixed
## allowlist (src, alt and title for an image; src for a video; width and
## height when all digits, which the page needs to hold the media's place
## while it loads), each value escaped, the last of a name winning, and
## only when its src is same-origin and root-relative. Anything else
## (onerror=, onload=, style=, an off-site or protocol-relative src) is
## dropped, and a tag that does not parse cleanly, or has no such src, is
## refused whole; the caller escapes it as text. A video gains `controls`
## and `preload="metadata"`, never autoplay. Pure, over bytes: the renderer
## (Md, MdInline) and the Images feed (Feeds, metal-vmm QUEUE 266) ask it.
import MdText
import Bytes

MdMedia := [].{

	## A rebuilt tag, and the index past the source it stood for.
	Rebuilt : {
		html : List(U8),
		end : U64,
	}

	## markdown_media `safeImgAt`: the `<img …>` at `raw[start]` rebuilt,
	## and the index past its `>`.
	img_at : List(U8), U64 -> Try(Rebuilt, [NotSafe])
	img_at = |raw, start| {
		tag = scan(raw, { start, name: Str.to_utf8("img") })?
		src = local_src(tag.attrs)?
		dims = digit_attrs(tag.attrs)
		texts = List.join_map(
			[Str.to_utf8("alt"), Str.to_utf8("title")],
			|name| match last_of(tag.attrs, name) {
				Ok(v) => attr(name, v)
				Err(Absent) => []
			},
		)
		Ok({
			html: List.join([
				Str.to_utf8("<img"),
				attr(Str.to_utf8("src"), src),
				texts,
				dims,
				['>'],
			]),
			end: tag.end,
		})
	}

	## markdown_media `safeVideoAt`: the `<video …></video>` pair at
	## `raw[start]` rebuilt as a locked player, and the index past its
	## `</video>`. Only whitespace may stand between the two tags: no
	## fallback content is carried through.
	video_at : List(U8), U64 -> Try(Rebuilt, [NotSafe])
	video_at = |raw, start| {
		tag = scan(raw, { start, name: Str.to_utf8("video") })?
		src = local_src(tag.attrs)?
		close = close_tag_end(raw, { at: skip_spaces(raw, tag.end), name: Str.to_utf8("video") })?
		Ok({
			html: List.join([
				Str.to_utf8("<video controls preload=\"metadata\""),
				attr(Str.to_utf8("src"), src),
				digit_attrs(tag.attrs),
				Str.to_utf8("></video>"),
			]),
			end: close,
		})
	}

	## The image tag `tag` (`<img …>`, from its `<`) rebuilt, or `Unsafe`:
	## the Images feed's door, `img_at` at the tag's start.
	rebuild : Str -> Try(Str, [Unsafe])
	rebuild = |tag| match img_at(Str.to_utf8(tag), 0) {
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

## markdown_media `tagNameAt` and `TagScan`: `<name` (any case) at `start`,
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

## markdown_media `matchCloseTag`: `</name>` at `at` (any case, spaces
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

## The src, when it is same-origin, as written (its ends' spaces kept).
local_src : List((List(U8), List(U8))) -> Try(List(U8), [NotSafe])
local_src = |attrs| match last_of(attrs, Str.to_utf8("src")) {
	Ok(src) => if is_local_url(Bytes.trim(src, Bytes.zig_spaces)) Ok(src) else Err(NotSafe)
	Err(Absent) => Err(NotSafe)
}

## Width and height, each kept only when all digits.
digit_attrs : List((List(U8), List(U8))) -> List(U8)
digit_attrs = |attrs| List.join_map(
	[Str.to_utf8("width"), Str.to_utf8("height")],
	|name| match last_of(attrs, name) {
		Ok(v) if MdText.is_all_digits(v) => attr(name, v)
		_ => []
	},
)

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

## ` name="value"`, the value escaped.
attr : List(U8), List(U8) -> List(U8)
attr = |name, value| List.append(
	MdText.escape_onto(
		List.join([
			[' '],
			name,
			['=', '"'],
		]),
		value,
	),
	'"',
)

# markdown_media's cases, each as its test has it.
img : Str -> Str
img = |raw| match MdMedia.img_at(Str.to_utf8(raw), 0) {
	Ok(r) => Str.from_utf8(r.html) ?? "not text"
	Err(NotSafe) => ""
}

video : Str -> Str
video = |raw| match MdMedia.video_at(Str.to_utf8(raw), 0) {
	Ok(r) => Str.from_utf8(r.html) ?? "not text"
	Err(NotSafe) => ""
}

expect img("<img src=\"/u/cat.png\" alt=\"a cat\" width=\"200\" onerror=\"x()\" style=\"z\">") == "<img src=\"/u/cat.png\" alt=\"a cat\" width=\"200\">"
expect img("<img src=\"/u/x.png\" width=\"320\" height=\"240\">") == "<img src=\"/u/x.png\" width=\"320\" height=\"240\">"
expect img("<img src=\"/u/x.png\" width=\"100%\" height=\"auto\">") == "<img src=\"/u/x.png\">"
expect img("<img src=\"https://evil/x.png\">") == ""
expect img("<img src=\"//evil/x.png\">") == ""
expect img("<img src=\"/\\evil\">") == ""
expect img("<img alt=\"no src\">") == ""
expect video("<video src=\"/u/clip.mp4\" width=\"640\" onerror=\"x()\"></video>") == "<video controls preload=\"metadata\" src=\"/u/clip.mp4\" width=\"640\"></video>"
expect video("<video src=\"https://evil/x.mp4\"></video>") == ""
expect video("<video src=\"/u/x.mp4\">") == ""
expect img("<img src=\"/\t/evil.example/x.png\">") == ""
expect img("<img src=\"/\n/evil.example/x.png\">") == ""
expect img("<img src=\"/\r\n/evil.example/x.png\">") == ""
expect img("<img src=\"/u/\\\\evil.example/x.png\">") == ""
expect video("<video src=\"/\t/evil.example/x.mp4\"></video>") == ""
expect img("<img src=\" /u/cat.png \">") == "<img src=\" /u/cat.png \">"
# The Images feed's (SafeImg's, folded here): its plants, escaped values,
# case-blind names, the last of a name winning, single quotes, a bare name.
expect MdMedia.rebuild("<img src=x onerror=\"alert(1)\">") == Err(Unsafe)
expect MdMedia.rebuild("<img src=\"/up/a.png\" width=\"40\" onload=\"alert(2)\">") == Ok("<img src=\"/up/a.png\" width=\"40\">")
expect MdMedia.rebuild("<IMG SRC='/a.png' alt=\"x\" ALT=y&z hidden>") == Ok("<img src=\"/a.png\" alt=\"y&amp;z\">")
expect MdMedia.rebuild("<img src=\"/a.png\" alt=\"<b>\">") == Ok("<img src=\"/a.png\" alt=\"&lt;b&gt;\">")
expect MdMedia.rebuild("<img src=\"/a.png\"") == Err(Unsafe)
expect MdMedia.rebuild("<img src=\"/a.png>") == Err(Unsafe)
expect MdMedia.rebuild("<img src=") == Err(Unsafe)
expect MdMedia.video_at(Str.to_utf8("x<VIDEO src=/v.mp4 >  </Video >y"), 1) == Ok({
	html: Str.to_utf8("<video controls preload=\"metadata\" src=\"/v.mp4\"></video>"),
	end: 31,
})
