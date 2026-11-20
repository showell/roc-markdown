## The dialect's definition: a chat message, or a page of a document, to HTML.
## This module is the API and the modes. The blocks are MdBlocks' and their own
## modules', each line's inline content is MdInline's, and every tag is MdHtml's.
##
## The parser is the judge of hostility: a render charges its work to a budget
## (MdText), checked at each block line and each inline step, and a message that
## blows it renders as `malformed_html` and is refused at POST (`hostility`).
## There is no second model of "too much" to drift from the parser. The judge
## (judge/judge.zig) holds every corpus case to its frozen html and `work_units`.
## Pure.
import MdBlocks
import MdChat
import MdDialect
import MdDocument
import MdHtml
import MdSafety
import MdText

Md := [].{

	## **WHAT THE HOST TELLS A RENDER**: which same-origin paths are its
	## uploads, the only places a member's `<img>`, `<video>` or
	## `![alt](src)` may load from (MdSafety.is_upload_url). Where a host
	## keeps its files is the host's to say: the renderer judges a src as a
	## URL, and asks this rule of one that passes. There is no default; a
	## host with no uploads passes `no_uploads`.
	##
	## And how a code block's body is shown (`code`): the host's hook may
	## color it, as HTML of the host's own that goes inside the renderer's
	## `<pre><code>`, or pass it to the renderer's escape. A quote-reply is
	## never offered. There is no default; a host that colors nothing passes
	## `plain_code`. The hook's work is the host's: the budget charges a code
	## block's body once, whatever the hook does with it.
	Options : { uploads : MdSafety.Uploads, code : Md.CodeHook }

	## See MdChat.CodeHook.
	CodeHook : MdChat.CodeHook

	## The code hook of a host that colors nothing: every code block's body is
	## the renderer's escape of it.
	plain_code : MdChat.CodeBlock -> [Colored(List(U8)), Plain]
	plain_code = |_| Plain

	## The rule of one uploads folder: every path under `prefix`.
	uploads_under : List(U8) -> MdSafety.Uploads
	uploads_under = |prefix| MdSafety.uploads_under(prefix)

	## The rule of a host with no uploads: every member's media is text.
	no_uploads : List(U8) -> Bool
	no_uploads = |_| Bool.False

	## A member's message, with its budget; a hostile one
	## is `malformed_html`.
	## `render` names the package's API, which roc-chat, roc-webbox and roc-apps'
	## book builder call by name.
	render : List(U8), Md.Options -> List(U8)
	render = |md, { uploads, code }| html_of(
		md,
		{
			wrap: HardWrap,
			budget: MdText.for_input(md),
			uploads,
			dialect: Chat(code),
		},
	)

	## Server-owned text, never a request's, with no
	## limit on its work. The depth cap and the escaping still hold.
	## `render` names the package's API, which roc-chat, roc-webbox and roc-apps'
	## book builder call by name.
	render_trusted : List(U8), Md.Options -> List(U8)
	render_trusted = |md, { uploads, code }| html_of(
		md,
		{
			wrap: HardWrap,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat(code),
		},
	)

	## Server-owned prose, whose source line
	## wraps join with a space rather than a `<br>`, so a span may cross one
	## and the text rewraps to the reader's width.
	## `render` names the package's API, which roc-chat, roc-webbox and roc-apps'
	## book builder call by name.
	render_trusted_reflow : List(U8), Md.Options -> List(U8)
	render_trusted_reflow = |md, { uploads, code }| html_of(
		md,
		{
			wrap: Reflow,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat(code),
		},
	)

	## See MdDocument.PageOptions.
	DocumentOptions : MdDocument.PageOptions

	## Server-owned prose as a page of a book. It has no budget and no chat
	## syntax, a newline is a space, a link to another site stays in its tab,
	## raw HTML is escaped, and each heading has an id. It adds what a chat
	## doesn't read: rules, indented code and `<http://…>`, and it leaves an
	## email as text. The hook is the one way in for HTML of the caller's own.
	## `render` names the package's API, which roc-chat, roc-webbox and roc-apps'
	## book builder call by name.
	render_document : List(U8), Md.DocumentOptions -> MdDocument.Page
	render_document = |md, options| {
		lines = MdDocument.with_plain_line_ends(md)
		MdDocument.with_heading_ids(
			html_of(
				lines,
				{
					wrap: Reflow,
					budget: MdText.unlimited,
					uploads: no_uploads,
					dialect: Document(options),
				},
			),
		)
	}

	## Text made safe for HTML, an element's content or an attribute's value
	## (either quote): `&`, `<`, `>`, `"` and `'` as entities, every other
	## byte as it is. The renderer's own escape, for a host's pages to share.
	escape : List(U8) -> List(U8)
	escape = |text| MdText.escape_onto([], text)

	## The work a render of `md` costs, unlimited, the
	## measure the budget caps.
	work_units : List(U8), Md.Options -> U64
	work_units = |md, { uploads, code }| match run(
		md,
		{
			wrap: HardWrap,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat(code),
		},
	) {
		Ok(done) => done.budget.spent
		Err(Hostile) => crash "Md.work_units: an unlimited budget blown"
	}

	## Whether `md` would blow its budget, so a POST
	## refuses it. One render in good faith with the real budget.
	hostility : List(U8), Md.Options -> [Renderable, TooMuchFormatting]
	hostility = |md, { uploads, code }| match run(
		md,
		{
			wrap: HardWrap,
			budget: MdText.for_input(md),
			uploads,
			dialect: Chat(code),
		},
	) {
		Ok(_) => Renderable
		Err(Hostile) => TooMuchFormatting
	}

	## The words a refused POST says.
	too_much_formatting : Str
	too_much_formatting = "too much markdown formatting"

	## What a hostile message renders as: an escaped paragraph, the client
	## free to style `.md-malformed`.
	malformed_html : List(U8)
	malformed_html = MdHtml.malformed
}

## The one seed every render grows from: `md`'s blocks from the top, as a
## document's, in `wrap` and against `budget`.
run : List(U8),
{
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> Try(MdText.Rendered, [Hostile])
run = |md, { wrap, budget, uploads, dialect }| MdBlocks.blocks_onto({
	out: [],
	md,
	spacing: Loose,
	depth: 0,
	wrap,
	budget,
	uploads,
	dialect,
})

html_of : List(U8),
{
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> List(U8)
html_of = |
	md,
	{ wrap, budget, uploads, dialect },
| match run(md, { wrap, budget, uploads, dialect }) {
	Ok(done) => done.out
	Err(Hostile) => Md.malformed_html
}
