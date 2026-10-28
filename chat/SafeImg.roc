## THE RENDERER'S RULE FOR AN `<img>` (angry-gopher markdown_media.zig
## `safeImgAt`): a tag a member wrote is never passed on as written. It is
## REBUILT from a fixed allowlist (src, alt, title, and width and height
## when all digits; each value HTML-escaped, the last of a name winning),
## and only when its src is same-origin and root-relative. Anything else
## (onerror=, onload=, style=, an off-site or protocol-relative src) is
## dropped, and a tag that does not parse cleanly, or has no such src, is
## refused whole. Pure, over bytes; the Images feed rebuilds every stored
## tag with it (Feeds.images_event, metal-vmm QUEUE 266).
import Ascii
import Bytes
SafeImg := [].{

	## The tag `tag` (`<img …>`, from its `<`) rebuilt, or `Unsafe`.
	rebuild : Str -> Try(Str, [Unsafe])
	rebuild = |tag| {
		s = tag.to_utf8()
		after = name_end(s)?
		attrs = scan(s, { at: after, out: [] })?
		src = last_of(attrs, "src")?
		if is_local(Bytes.trim(src, Bytes.zig_spaces)) {
			out = List.concat(Str.to_utf8("<img"), attr("src", src))
			with_text = [("alt", last_of(attrs, "alt")), ("title", last_of(attrs, "title"))]
				|> List.fold(
					out,
					|acc, (name, v)| match v {
						Ok(val) => List.concat(acc, attr(name, val))
						Err(_) => acc
					},
				)
			with_dims = [("width", last_of(attrs, "width")), ("height", last_of(attrs, "height"))]
				|> List.fold(
					with_text,
					|acc, (name, v)| match v {
						Ok(val) if is_all_digits(val) => List.concat(acc, attr(name, val))
						_ => acc
					},
				)
			match Str.from_utf8(List.append(with_dims, '>')) {
				Ok(t) => Ok(t)
				Err(_) => crash "SafeImg: a tag cut from text at ASCII bytes is text"
			}
		} else {
			Err(Unsafe)
		}
	}
}

## markdown_text `isSpace`: the five, not a vertical tab.
is_space : U8 -> Bool
is_space = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 12

## markdown_text `isAttrNameChar`.
is_name : U8 -> Bool
is_name = |c| Ascii.is_alphanumeric(c) or c == '-' or c == '_' or c == ':'

## markdown_media `tagNameAt`: `<img` (any case) then a space, `>` or `/`;
## the index past the name.
name_end : List(U8) -> Try(U64, [Unsafe])
name_end = |s|
	match List.take_first(s, 5) {
		[
			'<',
			i,
			m,
			g,
			d,
		] if Ascii.to_lower(i) == 'i' and Ascii.to_lower(m) == 'm' and Ascii.to_lower(g) == 'g' and (is_space(d) or d == '>' or d == '/') => Ok(4)
		_ => Err(Unsafe)
	}

## markdown_media `TagScan`: each `name=value` from `i` to the tag's `>`,
## names lowered, quotes respected, a bare name's value empty. Running off
## the end, a name of no name bytes, or `=` with nothing after is `Unsafe`.
scan : List(U8),
{
	at : U64,
	out : List((List(U8), List(U8))),
} -> Try(List((List(U8), List(U8))), [Unsafe])
scan = |s, { at: i, out }|
	match List.get(s, i) {
		Err(_) => Err(Unsafe)
		Ok(c) if is_space(c) or c == '/' => scan(s, { at: i + 1, out })
		Ok('>') => Ok(out)
		Ok(_) => {
			e = Bytes.count_while(s, { keep: is_name, at: i })
			if e == i {
				Err(Unsafe)
			} else {
				name = List.map(List.sublist(s, { start: i, len: e - i }), Ascii.to_lower)
				j = Bytes.count_while(s, { keep: is_space, at: e })
				match List.get(s, j) {
					Ok('=') => {
						k = Bytes.count_while(s, { keep: is_space, at: j + 1 })
						match List.get(s, k) {
							Err(_) => Err(Unsafe)
							Ok(q) if q == '"' or q == '\'' => {
								close = Bytes.find_byte(
									s,
									{ byte: q, at: k + 1 },
								).map_err(|_| Unsafe)?
								scan(
									s,
									{
										at: close + 1,
										out: List.append(
											out,
											(
												name,
												List.sublist(
													s,
													{ start: k + 1, len: close - k - 1 },
												),
											),
										),
									},
								)
							}
							Ok(_) => {
								v = Bytes.count_while(
									s,
									{ keep: |b| !is_space(b) and b != '>', at: k },
								)
								scan(
									s,
									{
										at: v,
										out: List.append(
											out,
											(name, List.sublist(s, { start: k, len: v - k })),
										),
									},
								)
							}
						}
					}
					_ => scan(s, { at: j, out: List.append(out, (name, [])) })
				}
			}
		}
	}

## The last value of attribute `name`.
last_of : List((List(U8), List(U8))), Str -> Try(List(U8), [Unsafe])
last_of = |attrs, name| {
	want = name.to_utf8()
	List.fold(
		attrs,
		Err(Unsafe),
		|got, (n, v)| if n == want Ok(v) else got,
	)
}

## markdown_media `isLocalUrl`: `/` then anything but `/` or `\`, and no
## control byte or backslash anywhere: a browser strips tabs and newlines
## inside a URL and reads `\` as `/`, so `/\t/evil` is `//evil`.
is_local : List(U8) -> Bool
is_local = |src|
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

is_all_digits : List(U8) -> Bool
is_all_digits = |v| v != [] and List.all(v, Ascii.is_digit)

## ` name="value"`, the value as markdown_text `escapeInto` escapes it.
attr : Str, List(U8) -> List(U8)
attr = |name, val| {
	esc = List.fold(
		val,
		[],
		|out, c| match c {
			'&' => List.concat(out, Str.to_utf8("&amp;"))
			'<' => List.concat(out, Str.to_utf8("&lt;"))
			'>' => List.concat(out, Str.to_utf8("&gt;"))
			'"' => List.concat(out, Str.to_utf8("&quot;"))
			_ => List.append(out, c)
		},
	)
	List.concat(List.concat(Str.to_utf8(" ${name}=\""), esc), ['"'])
}

# markdown_media's cases, each as its test has it.
# The allowlist: src, alt and width kept; onerror and style dropped.
expect SafeImg.rebuild("<img src=\"/u/cat.png\" alt=\"a cat\" width=\"200\" onerror=\"x()\" style=\"z\">") == Ok("<img src=\"/u/cat.png\" alt=\"a cat\" width=\"200\">")
# Digit dims kept; any other dim dropped, not echoed.
expect SafeImg.rebuild("<img src=\"/u/x.png\" width=\"320\" height=\"240\">") == Ok("<img src=\"/u/x.png\" width=\"320\" height=\"240\">")
expect SafeImg.rebuild("<img src=\"/u/x.png\" width=\"100%\" height=\"auto\">") == Ok("<img src=\"/u/x.png\">")
# The same-origin gate: absolute, protocol-relative, the backslash trick, no src.
expect SafeImg.rebuild("<img src=\"https://evil/x.png\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"//evil/x.png\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/\\evil\">") == Err(Unsafe)
expect SafeImg.rebuild("<img alt=\"no src\">") == Err(Unsafe)
# A tab, newline or backslash inside the src is refused (metal-vmm QUEUE 172).
expect SafeImg.rebuild("<img src=\"/\t/evil.example/x.png\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/\n/evil.example/x.png\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/\r\n/evil.example/x.png\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/u/\\\\evil.example/x.png\">") == Err(Unsafe)
# A same-origin src with a space around it stays, as written.
expect SafeImg.rebuild("<img src=\" /u/cat.png \">") == Ok("<img src=\" /u/cat.png \">")
# The feed's own plants (images_store's test): the unquoted onerror, an onload beside kept dims.
expect SafeImg.rebuild("<img src=x onerror=\"alert(1)\">") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/up/a.png\" width=\"40\" onload=\"alert(2)\">") == Ok("<img src=\"/up/a.png\" width=\"40\">")
# Escaped values, case-blind names, the last of a name winning, single quotes, a bare name.
expect SafeImg.rebuild("<IMG SRC='/a.png' alt=\"x\" ALT=y&z hidden>") == Ok("<img src=\"/a.png\" alt=\"y&amp;z\">")
expect SafeImg.rebuild("<img src=\"/a.png\" alt=\"<b>\">") == Ok("<img src=\"/a.png\" alt=\"&lt;b&gt;\">")
# Unclosed, a quote never closed, `=` at the end: refused whole.
expect SafeImg.rebuild("<img src=\"/a.png\"") == Err(Unsafe)
expect SafeImg.rebuild("<img src=\"/a.png>") == Err(Unsafe)
expect SafeImg.rebuild("<img src=") == Err(Unsafe)
