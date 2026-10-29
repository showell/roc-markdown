## **WHAT THE PLAYGROUND SHOWS FOR A MESSAGE** (playground/md_wasm.js reads
## it): three answers from the package, each as bytes, in this order: the
## mode's html, the work units (decimal digits) and the hostility's words
## (none when renderable). The mode is a number at the wasm edge: 0 the
## chat's `render`, 1 `render_trusted`, 2 `render_trusted_reflow`.
app [answer] {
	md: "../package/main.roc",
	pf: platform "platform/main.roc",
}

import md.Md

answer : List(U8), U8 -> List(List(U8))
answer = |text, mode| [
	match mode_of(mode) {
		Chat => Md.render(text)
		Trusted => Md.render_trusted(text)
		Reflow => Md.render_trusted_reflow(text)
	},
	Str.to_utf8(U64.to_str(Md.work_units(text))),
	match Md.hostility(text) {
		Renderable => []
		TooMuchFormatting => Str.to_utf8(Md.too_much_formatting)
	},
]

## **A MODE THE PAGE CANNOT NAME IS A CRASH**, never a render in some other
## mode.
mode_of : U8 -> [Chat, Trusted, Reflow]
mode_of = |n| match n {
	0 => Chat
	1 => Trusted
	2 => Reflow
	_ => crash "the playground's mode is 0, 1 or 2"
}
