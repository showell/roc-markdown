## A raw HTML block, which is escaped but for the media a host's uploads allow.
## Pure.
import Ascii
import MdMedia
import MdSafety
import MdText

MdRawHtml := [].{

	## A raw block, every same-origin `<img>` and
	## `<video>` rebuilt (MdMedia), every other byte escaped. One unit a byte.
	raw_html_onto : List(U8), { md : List(U8), line_start : U64, budget : MdText.Budget, uploads : MdSafety.Uploads } -> MdText.Block
	raw_html_onto = |out, { md, line_start, budget, uploads }| {
		# CommonMark's type 7: only at a block's start, and up to a blank line,
		# with no <p> and no newline added.
		md_len = md.len()
		var $p = MdText.next_line(md, MdText.line_end(md, line_start))
		while $p < md_len and !MdText.is_blank(MdText.cut(md, { start: $p, end: MdText.line_end(md, $p) })) {
			$p = MdText.next_line(md, MdText.line_end(md, $p))
		}
		raw = MdText.cut(md, { start: line_start, end: $p })
		len = raw.len()
		var $out = out
		var $last = 0
		var $i = 0
		while $i < len {
			if MdText.at(raw, $i) != '<' {
				$i = $i + 1
			} else {
				safe = match MdMedia.img_at(raw, $i, uploads) {
					Ok(tag) => Ok(tag)
					Err(NotSafe) => MdMedia.video_at(raw, $i, uploads)
				}
				match safe {
					Ok(tag) => {
						$out = MdText.escape_onto($out, MdText.cut(raw, { start: $last, end: $i })).concat(tag.html)
						$i = tag.end
						$last = tag.end
					}
					Err(NotSafe) => {
						$i = $i + 1
					}
				}
			}
		}
		{
			out: MdText.escape_onto($out, raw.drop_first($last)),
			budget: MdText.charge(budget, len),
			after: $p,
		}
	}

	## A whole open or close tag, then only
	## whitespace (CommonMark's type 7).
	is_html_block_start : List(U8) -> Bool
	is_html_block_start = |line| {
		t = MdText.trim_line(line)
		match t {
			['<', second, ..] if Ascii.is_letter(second) or second == '/' =>
				match html_tag_end(t) {
					Ok(end) => MdText.is_blank(t.drop_first(end))
					Err(Unterminated) => Bool.False
				}
			_ => Bool.False
		}
	}
}

## The index past the `>` closing the tag at `t[0]`,
## quoted values respected.
html_tag_end : List(U8) -> Try(U64, [Unterminated])
html_tag_end = |t| {
	len = t.len()
	var $i = 1
	while $i < len {
		c = MdText.at(t, $i)
		if c == '"' or c == '\'' {
			close = MdText.find_or_end(t, { byte: c, at: $i + 1 })
			if close >= len {
				return Err(Unterminated)
			} else {
				$i = close + 1
			}
		} else if c == '>' {
			return Ok($i + 1)
		} else {
			$i = $i + 1
		}
	}
	Err(Unterminated)
}
