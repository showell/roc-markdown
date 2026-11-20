## **WHAT THE JUDGE HOLDS EACH CASE TO** (judge/judge.zig): a message's five
## answers from the package, in this order, each as bytes: `render`'s html,
## the work units (decimal digits), the hostility's words (none when
## renderable), `render_trusted`'s html and `render_trusted_reflow`'s html.
##
## **EACH CORPUS RENDERS UNDER THE UPLOADS RULE ITS CASES WERE WRITTEN FOR**
## (judge/data/corpora.txt names it), as a host would pass it:
##   - `user-uploads`: under `/user_uploads/`, roc-chat's;
##   - `same-origin`: any same-origin path, the rule the Zig renderer's own
##     tests were written against;
##   - `old-chat`: the old chat's, `<base>/<topic>/uploads/<file>` with
##     `<base>` a DM's `/chat/c/<pair>` or a channel's `/channel/<name>`.
app [answers] { md: "../package/main.roc", pf: platform "./platform/main.roc" }

import md.Md

answers : List(U8), List(U8) -> List(List(U8))
answers = |text, rule| {
	options = { uploads: uploads_of(rule), code: Md.plain_code }
	[
		Md.render(text, options),
		Md.work_units(text, options).to_str().to_utf8(),
		match Md.hostility(text, options) {
			Renderable => []
			TooMuchFormatting => Md.too_much_formatting.to_utf8()
		},
		Md.render_trusted(text, options),
		Md.render_trusted_reflow(text, options),
	]
}

## The rule a corpus names; a name the judge does not know is its bug.
uploads_of : List(U8) -> (List(U8) -> Bool)
uploads_of = |rule|
	if rule == "user-uploads".to_utf8() {
		Md.uploads_under("/user_uploads/".to_utf8())
	} else if rule == "same-origin".to_utf8() {
		|_| Bool.True
	} else if rule == "old-chat".to_utf8() {
		is_old_chat_upload
	} else {
		crash "judge/answers.roc: no uploads rule of that name"
	}

## The old chat's upload: `/chat/c/<pair>/<topic>/uploads/<file>` or
## `/channel/<name>/<topic>/uploads/<file>`, each part not empty.
is_old_chat_upload : List(U8) -> Bool
is_old_chat_upload = |path| {
	word = Str.to_utf8
	filled = |parts| parts.all(|p| !p.is_empty())
	dm_words = [
		[],
		word("chat"),
		word("c"),
		word("uploads"),
	]
	channel_words = [[], word("channel"), word("uploads")]
	match path.split_on('/') {
		[
			root,
			chat,
			conversation,
			pair,
			topic,
			uploads,
			file,
		] if [root, chat, conversation, uploads] == dm_words => filled([pair, topic, file])
		[
			root,
			channel,
			name,
			topic,
			uploads,
			file,
		] if [root, channel, uploads] == channel_words => filled([name, topic, file])
		_ => Bool.False
	}
}

expect is_old_chat_upload("/chat/c/1_3/yo/uploads/abc.mp4".to_utf8())
expect is_old_chat_upload("/channel/general/plans/uploads/x.png".to_utf8())
expect !is_old_chat_upload("/chat/c/1_3/yo/upload".to_utf8())
expect !is_old_chat_upload("/chat/c//yo/uploads/abc.mp4".to_utf8())
expect !is_old_chat_upload("/user_uploads/a.png".to_utf8())
