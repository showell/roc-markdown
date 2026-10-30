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
app [answers] {
	md: "../package/main.roc",
	pf: platform "platform/main.roc",
}

import md.Md

answers : List(U8), List(U8) -> List(List(U8))
answers = |text, rule| {
	options = { uploads: uploads_of(rule) }
	[
		Md.render(text, options),
		Str.to_utf8(U64.to_str(Md.work_units(text, options))),
		match Md.hostility(text, options) {
			Renderable => []
			TooMuchFormatting => Str.to_utf8(Md.too_much_formatting)
		},
		Md.render_trusted(text, options),
		Md.render_trusted_reflow(text, options),
	]
}

## The rule a corpus names; a name the judge does not know is its bug.
uploads_of : List(U8) -> (List(U8) -> Bool)
uploads_of = |rule|
	if rule == Str.to_utf8("user-uploads") {
		Md.uploads_under(Str.to_utf8("/user_uploads/"))
	} else if rule == Str.to_utf8("same-origin") {
		|_| Bool.True
	} else if rule == Str.to_utf8("old-chat") {
		is_old_chat_upload
	} else {
		crash "judge/answers.roc: no uploads rule of that name"
	}

## The old chat's upload: `/chat/c/<pair>/<topic>/uploads/<file>` or
## `/channel/<name>/<topic>/uploads/<file>`, each part not empty.
is_old_chat_upload : List(U8) -> Bool
is_old_chat_upload = |path| {
	word = Str.to_utf8
	filled = |parts| List.all(parts, |p| !List.is_empty(p))
	match List.split_on(path, '/') {
		[root, chat, c, pair, topic, uploads, file] if root == [] and chat == word("chat") and c == word("c") and uploads == word("uploads") => filled([pair, topic, file])
		[root, channel, name, topic, uploads, file] if root == [] and channel == word("channel") and uploads == word("uploads") => filled([name, topic, file])
		_ => Bool.False
	}
}

expect is_old_chat_upload(Str.to_utf8("/chat/c/1_3/yo/uploads/abc.mp4"))
expect is_old_chat_upload(Str.to_utf8("/channel/general/plans/uploads/x.png"))
expect !is_old_chat_upload(Str.to_utf8("/chat/c/1_3/yo/upload"))
expect !is_old_chat_upload(Str.to_utf8("/chat/c//yo/uploads/abc.mp4"))
expect !is_old_chat_upload(Str.to_utf8("/user_uploads/a.png"))
