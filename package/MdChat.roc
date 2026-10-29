## **THE CHAT'S OWN EXTENSIONS TO THE MARKDOWN**, the dialect's parts that
## are neither CommonMark's nor GFM's, in one place: a fork building
## something that is no chat takes them out here, and a fork building another
## chat (`@mentions`, `#channels`) adds its own beside them. The renderer
## asks here at fixed points, plain calls and no plugin system:
##   - the inline pass (MdInline), at each byte of a line not inside a link's
##     label, for a reference (`reference_at`);
##   - the fence's renderer (Md), for a fence that is a quote-reply
##     (`is_quote_fence`);
##   - the fence's grammar (MdFence), for the longest run that opens one
##     (`max_fence_run`);
##   - the media rule (MdSafety), for the folder the chat serves its uploads
##     from, the one place an `<img>`, a `<video>` or an `![alt](src)` may
##     point (`uploads_prefix`).
##
## Their markup is MdHtml's (`msg_ref`, `chat_quote_open`); what else a
## media src must be (no `..`, no control byte) is MdSafety's. Pure.
import Ascii
import Bytes
import MdHtml
import MdText

MdChat := [].{

	## markdown_links `msgRefEnd` and `appendMsgRef`: a message reference,
	## `\bMSG_([A-Za-z0-9-]+_[0-9]+)\b`, at `i`: its link, and the index past
	## it. The pass reads one first, whole, as its `_`s would otherwise be read
	## as emphasis and split it.
	reference_at : List(U8), U64 -> Try({ html : List(U8), end : U64 }, [NoRef])
	reference_at = |text, i|
		if MdText.at(text, i) != 'M' {
			Err(NoRef)
		} else {
			end = msg_ref_end(text, i)?
			Ok({
				html: MdHtml.msg_ref({
					slug: MdText.cut(text, { start: i + List.len(msg_prefix), end }),
					label: MdText.cut(text, { start: i, end }),
				}),
				end,
			})
		}

	## The quote-reply: a fence whose language is `quote` holds a quoted
	## message, rendered as preformatted text and not as code.
	is_quote_fence : List(U8) -> Bool
	is_quote_fence = |lang| lang == Str.to_utf8("quote")

	## markdown_fence `max_nest_levels` (8) plus 2: a level-8 quote-reply
	## opens with 10 characters, and a longer run is no fence (MdFence).
	max_fence_run : U64
	max_fence_run = 10

	## Where the chat serves its members' uploads, and so the only path a
	## member's media may load: never one of the app's own routes (a held
	## `/conversations/1/stream`, `/login`), which an image would make every
	## reader's browser fetch.
	uploads_prefix : List(U8)
	uploads_prefix = Str.to_utf8("/user_uploads/")
}

msg_ref_end : List(U8), U64 -> Try(U64, [NoRef])
msg_ref_end = |text, i| {
	len = List.len(text)
	n = List.len(msg_prefix)
	if i + n > len or MdText.cut(text, { start: i, end: i + n }) != msg_prefix {
		Err(NoRef)
	} else if i > 0 and MdText.is_word_char(MdText.at(text, i - 1)) {
		Err(NoRef)
	} else {
		slug_end = Bytes.count_while(text, { keep: is_slug_char, at: i + n })
		if slug_end == i + n or slug_end >= len or MdText.at(text, slug_end) != '_' {
			Err(NoRef)
		} else {
			end = Bytes.count_while(text, { keep: Ascii.is_digit, at: slug_end + 1 })
			if end == slug_end + 1 or (
				end < len and MdText.is_word_char(
					MdText.at(
						text,
						end,
					),
				)
			) Err(NoRef) else Ok(end)
		}
	}
}

## markdown_text `isSlugChar`: a `MSG_` reference's slug.
is_slug_char : U8 -> Bool
is_slug_char = |c| Ascii.is_alphanumeric(c) or c == '-'

msg_prefix : List(U8)
msg_prefix = Str.to_utf8("MSG_")

expect MdChat.reference_at(Str.to_utf8("MSG_plans_3."), 0) == Ok({ html: Str.to_utf8("<a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a>"), end: 11 })
expect MdChat.reference_at(Str.to_utf8("xMSG_plans_3"), 1) == Err(NoRef)
expect MdChat.reference_at(Str.to_utf8("MSG_plans_"), 0) == Err(NoRef)
