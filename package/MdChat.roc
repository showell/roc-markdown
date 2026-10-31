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
##     (`max_fence_run`).
##
## Where a chat keeps its uploads is no part of the dialect: the host names
## them in each render's options (Md.Options). Their markup is MdHtml's
## (`msg_ref`, `chat_quote_open`). Pure.
import Ascii
import Bytes
import MdHtml
import MdText

MdChat := [].{

	## A message reference at `i`: its link, and the index past it. Two forms,
	## each between word boundaries:
	##   - `\bMSG_([A-Za-z0-9-]+_[0-9]+)\b`, a topic's message, on this page
	##     only;
	##   - `\bMSG_([A-Za-z][A-Za-z0-9-]{0,39}\.[A-Za-z0-9-]+_[0-9]+)\b`, a
	##     channel's topic's message.
	## Neither name can hold a `.` or a `_`, so a reference reads one way only.
	## Both link to `#msg-<slug>`, naming no URL: where a reference goes is the
	## host's to decide. The pass reads one first, whole, as its `_`s would
	## otherwise be read as emphasis and split it.
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
	is_quote_fence = |lang| lang == "quote".to_utf8()

	## Eight quote-reply levels, plus 2: a level-8 quote-reply
	## opens with 10 characters, and a longer run is no fence (MdFence).
	max_fence_run : U64
	max_fence_run = 10
}

msg_ref_end : List(U8), U64 -> Try(U64, [NoRef])
msg_ref_end = |text, i| {
	len = text.len()
	n = msg_prefix.len()
	if i + n > len or MdText.cut(text, { start: i, end: i + n }) != msg_prefix {
		Err(NoRef)
	} else if i > 0 and MdText.is_word_char(MdText.at(text, i - 1)) {
		Err(NoRef)
	} else {
		first_end = slug_end(text, i + n)?
		topic_end = long_topic_end(text, { channel_start: i + n, first_end })?
		if topic_end >= len or MdText.at(text, topic_end) != '_' {
			Err(NoRef)
		} else {
			end = Bytes.count_while(text, { keep: Ascii.is_digit, at: topic_end + 1 })
			if end == topic_end + 1 or (end < len and MdText.is_word_char(MdText.at(text, end))) {
				Err(NoRef)
			} else {
				Ok(end)
			}
		}
	}
}

## Where the topic's slug ends: at `first_end` for the short form; for the
## long form (a `.` after the first run), past the second run, when what
## came first is a channel's name.
long_topic_end : List(U8), { channel_start : U64, first_end : U64 } -> Try(U64, [NoRef])
long_topic_end = |text, { channel_start, first_end }|
	if first_end >= text.len() or MdText.at(text, first_end) != '.' {
		Ok(first_end)
	} else if first_end - channel_start > channel_name_max or !Ascii.is_letter(MdText.at(text, channel_start)) {
		Err(NoRef)
	} else {
		slug_end(text, first_end + 1)
	}

## The end of a run of slug characters from `start`, or no reference for none.
slug_end : List(U8), U64 -> Try(U64, [NoRef])
slug_end = |text, start| {
	end = Bytes.count_while(text, { keep: is_slug_char, at: start })
	if (end == start) Err(NoRef) else Ok(end)
}

## The longest channel name, in bytes (a channel is a letter, then letters,
## digits and hyphens).
channel_name_max : U64
channel_name_max = 40

## A `MSG_` reference's slug.
is_slug_char : U8 -> Bool
is_slug_char = |c| Ascii.is_alphanumeric(c) or c == '-'

msg_prefix : List(U8)
msg_prefix = "MSG_".to_utf8()

expect MdChat.reference_at("MSG_plans_3.".to_utf8(), 0) == Ok({ html: "<a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a>".to_utf8(), end: 11 })
expect MdChat.reference_at("xMSG_plans_3".to_utf8(), 1) == Err(NoRef)
expect MdChat.reference_at("MSG_plans_".to_utf8(), 0) == Err(NoRef)

# A channel's reference: its name, a `.`, then the topic's reference.
expect MdChat.reference_at("MSG_Cobblestone.ChitChat_5.".to_utf8(), 0) == Ok({ html: "<a href=\"#msg-Cobblestone.ChitChat_5\" class=\"msg-ref\">MSG_Cobblestone.ChitChat_5</a>".to_utf8(), end: 26 })
expect MdChat.reference_at("MSG_a-1-.road-trip_9 x".to_utf8(), 0).map_ok(|r| r.end) == Ok(20)
expect MdChat.reference_at("MSG_${Str.repeat("a", 40)}.t_1".to_utf8(), 0).map_ok(|r| r.end) == Ok(48)
# Not one: no number, a name too long, a channel not led by a letter, an
# empty name, two dots, a word character after.
expect MdChat.reference_at("MSG_x.y".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_x.y_".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_${Str.repeat("a", 41)}.t_1".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_1st.ChitChat_5".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_-a.ChitChat_5".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_.ChitChat_5".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_a._5".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_a.b.c_5".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("MSG_a.b_5x".to_utf8(), 0) == Err(NoRef)
expect MdChat.reference_at("xMSG_a.b_5".to_utf8(), 1) == Err(NoRef)
