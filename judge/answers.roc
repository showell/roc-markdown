## **WHAT THE JUDGE HOLDS EACH CASE TO** (judge/judge.zig): a message's five
## answers from the package, in this order, each as bytes: `render`'s html,
## the work units (decimal digits), the hostility's words (none when
## renderable), `render_trusted`'s html and `render_trusted_reflow`'s html.
app [answers] {
	md: "../package/main.roc",
	pf: platform "platform/main.roc",
}

import md.Md

answers : List(U8) -> List(List(U8))
answers = |text| [
	Md.render(text),
	Str.to_utf8(U64.to_str(Md.work_units(text))),
	match Md.hostility(text) {
		Renderable => []
		TooMuchFormatting => Str.to_utf8(Md.too_much_formatting)
	},
	Md.render_trusted(text),
	Md.render_trusted_reflow(text),
]
