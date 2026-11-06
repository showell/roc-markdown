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
	Options : { uploads : MdSafety.Uploads }

	## The rule of one uploads folder: every path under `prefix`.
	uploads_under : List(U8) -> MdSafety.Uploads
	uploads_under = |prefix| MdSafety.under(prefix)

	## The rule of a host with no uploads: every member's media is text.
	no_uploads : MdSafety.Uploads
	no_uploads = |_| Bool.False

	## A member's message, with its budget; a hostile one
	## is `malformed_html`.
	render : List(U8), Md.Options -> List(U8)
	render = |md, { uploads }| render_html(
		md,
		{
			wrap: HardWrap,
			budget: MdText.for_input(md),
			uploads,
			dialect: Chat,
		},
	)

	## Server-owned text, never a request's, with no
	## limit on its work. The depth cap and the escaping still hold.
	render_trusted : List(U8), Md.Options -> List(U8)
	render_trusted = |md, { uploads }| render_html(
		md,
		{
			wrap: HardWrap,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat,
		},
	)

	## Server-owned prose, whose source line
	## wraps join with a space rather than a `<br>`, so a span may cross one
	## and the text rewraps to the reader's width.
	render_trusted_reflow : List(U8), Md.Options -> List(U8)
	render_trusted_reflow = |md, { uploads }| render_html(
		md,
		{
			wrap: Reflow,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat,
		},
	)

	## See MdDocument.PageOptions.
	DocumentOptions : MdDocument.PageOptions

	## Server-owned prose as a page of a book. It has no budget and no chat
	## syntax, a newline is a space, a link to another site stays in its tab,
	## raw HTML is escaped, and each heading has an id. It adds what a chat
	## doesn't read: rules, indented code and `<http://…>`, and it leaves an
	## email as text. The hook is the one way in for HTML of the caller's own.
	render_document : List(U8), Md.DocumentOptions -> MdDocument.Page
	render_document = |md, options| {
		lines = MdDocument.with_plain_line_ends(md)
		MdDocument.with_heading_ids(
			render_html(
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
	work_units = |md, { uploads }| match run(
		md,
		{
			wrap: HardWrap,
			budget: MdText.unlimited,
			uploads,
			dialect: Chat,
		},
	) {
		Ok(done) => done.budget.spent
		Err(Hostile) => crash "Md.work_units: an unlimited budget blown"
	}

	## Whether `md` would blow its budget, so a POST
	## refuses it. One render in good faith with the real budget.
	hostility : List(U8), Md.Options -> [Renderable, TooMuchFormatting]
	hostility = |md, { uploads }| match run(
		md,
		{
			wrap: HardWrap,
			budget: MdText.for_input(md),
			uploads,
			dialect: Chat,
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

render_html : List(U8),
{
	wrap : [HardWrap, Reflow],
	budget : MdText.Budget,
	uploads : MdSafety.Uploads,
	dialect : MdDialect.Dialect,
} -> List(U8)
render_html = |
	md,
	{ wrap, budget, uploads, dialect },
| match run(md, { wrap, budget, uploads, dialect }) {
	Ok(done) => done.out
	Err(Hostile) => Md.malformed_html
}

# The chat's own options, as roc-chat passes them.
chat : Md.Options
chat = { uploads: Md.uploads_under("/user_uploads/".to_utf8()) }

md : Str -> Str

md = |text| Str.from_utf8(Md.render(text.to_utf8(), chat)) ?? crash "a test's text is UTF-8"

# Whole messages, block by block: the media rule, hard wraps and their
# backslash, fences, lists, quotes and headings as the dialect renders them.
expect md("<video src=\"/user_uploads/1_3/abc.mp4\"></video>") == "<p><video controls preload=\"metadata\" src=\"/user_uploads/1_3/abc.mp4\"></video></p>\n"
# Media outside the host's uploads is text: under roc-chat's rule, the old
# chat's upload paths too.
expect md("<video src=\"/chat/c/1_3/yo/uploads/abc.mp4\"></video>") == "<p>&lt;video src=&quot;/chat/c/1_3/yo/uploads/abc.mp4&quot;&gt;&lt;/video&gt;</p>\n"
expect md("hello\nworld") == "<p>hello<br>\nworld</p>\n"
expect Md.escape("Bea <i>x</i> & \"co\" 'q'".to_utf8()) == "Bea &lt;i&gt;x&lt;/i&gt; &amp; &quot;co&quot; &#39;q&#39;".to_utf8()
expect md("hello\\\nworld") == "<p>hello<br>\nworld</p>\n"
expect md("hello\\\\\nworld") == "<p>hello\\<br>\nworld</p>\n"
expect md("hello\\") == "<p>hello\\</p>\n"
expect Str.from_utf8(
	Md.render_trusted_reflow("*a\\\nb* c\nd".to_utf8(), chat),
) == Ok("<p>*a<br>\nb* c d</p>\n")
expect md("# about MSG_plans_3") == "<h1>about <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></h1>\n"
expect md("```zig\na<b\n```\nafter") == "<pre><code class=\"language-zig\">a&lt;b\n</code></pre>\n<p>after</p>\n"
expect md("- a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"
# A blank line inside an item stays: two paragraphs, a fence's blank line.
expect md("- one\n\n  two") == "<ul>\n<li>\n<p>one</p>\n<p>two</p>\n</li>\n</ul>\n"
expect md("- ```\n  a\n\n  b") == "<ul>\n<li>\n<pre><code>a\n\nb\n</code></pre>\n</li>\n</ul>\n"
expect md("> q\nlazy") == "<blockquote>\n<p>q<br>\nlazy</p>\n</blockquote>\n"
expect Str.from_utf8(
	Md.render_trusted_reflow("A **bold phrase that\nspans two lines** here.".to_utf8(), chat),
) == Ok("<p>A <strong>bold phrase that spans two lines</strong> here.</p>\n")
expect Md.hostility("some **bold** text and a [link](http://x.com)".to_utf8(), chat) == Renderable
# A render's cost grows with what it reads. The judge freezes the exact units.
expect Md.work_units("a".to_utf8(), chat) < Md.work_units("**a** b".to_utf8(), chat)
# GFM's tables.
expect md("| a | b |\n| :- | -: |\n| c |\n| d | e | f |") == "<table>\n<thead>\n<tr>\n<th align=\"left\">a</th>\n<th align=\"right\">b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">c</td>\n<td align=\"right\"></td>\n</tr>\n<tr>\n<td align=\"left\">d</td>\n<td align=\"right\">e</td>\n</tr>\n</tbody>\n</table>\n"
expect md("see:\n| a |\n| - |\n\nafter") == "<p>see:</p>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>\n<p>after</p>\n"
expect md("| a | b |\n| - |") == "<p>| a | b |<br>\n| - |</p>\n"
# A pipe in a code span splits its cell all the same: GFM splits first.
expect md("| a | b |\n| - | - |\n| `x|y` |") == "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>`x</td>\n<td>y`</td>\n</tr>\n</tbody>\n</table>\n"
# A tight item whose first child is a table starts it on a line of its own.
expect md("- | a |\n  | - |\n  | b |\n- next") == "<ul>\n<li>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n</li>\n<li>next</li>\n</ul>\n"
# No line is lazy after a quoted table: its rows are no paragraph.
expect md("> | a |\n> | - |\n> | MSG_x_1 |\nlazy") == "<blockquote>\n<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><a href=\"#msg-x_1\" class=\"msg-ref\">MSG_x_1</a></td>\n</tr>\n</tbody>\n</table>\n</blockquote>\n<p>lazy</p>\n"

# A document's render, and a chat's of the same text beside it.
widgets : MdDocument.FenceHook
widgets = |{ tag, args, body }|
	if tag == "widget".to_utf8() {
		Html("<iframe src=\"/w/".to_utf8().concat(args).concat("\"></iframe>\n".to_utf8()))
	} else if tag == "dot".to_utf8() {
		Html("<svg>".to_utf8().concat(body).concat("</svg>\n".to_utf8()))
	} else if tag == "raw".to_utf8() {
		Html("<h2 id=\"\">x</h2>\n".to_utf8())
	} else if tag == "heading".to_utf8() {
		Html("<h2>mine</h2>\n<h2 id=\"x\">too</h2>\n".to_utf8())
	} else {
		Pass
	}

doc : Str -> Str
doc = |text| Str.from_utf8(
	Md.render_document(text.to_utf8(), { fence: widgets, images: AsLinks }).html,
) ?? crash "a test's text is UTF-8"

# A document that shows its images, as the essay notes do.
page_with_images : Str -> Str
page_with_images = |text| Str.from_utf8(
	Md.render_document(text.to_utf8(), { fence: widgets, images: Shown }).html,
) ?? crash "a test's text is UTF-8"

# The hook answers with HTML, unescaped, or passes the fence on as code.
expect doc("```widget sky\n```\n") == "<iframe src=\"/w/sky\"></iframe>\n"
expect doc("```dot\na -> b\n```") == "<svg>a -> b\n</svg>\n"
expect doc("```roc\na<b\n```") == "<pre><code class=\"language-roc\">a&lt;b\n</code></pre>\n"
expect doc("```\na\n```") == "<pre><code>a\n</code></pre>\n"
expect doc("  ```dot\n  a\n   b\n  ```") == "<svg>a\n b\n</svg>\n"
expect doc("- x\n\n  ```dot\n  a\n  ```\n") == "<ul>\n<li>\n<p>x</p>\n<svg>a\n</svg>\n</li>\n</ul>\n"
# A chat has no hook, so the same fences are code.
expect md("```widget sky\n```\n") == "<pre><code class=\"language-widget\"></code></pre>\n"
expect md("```dot\na -> b\n```") == "<pre><code class=\"language-dot\">a -&gt; b\n</code></pre>\n"

# The chat's syntax is off in a document, and on in a chat.
expect doc("see MSG_plans_3") == "<p>see MSG_plans_3</p>\n"
expect md("see MSG_plans_3") == "<p>see <a href=\"#msg-plans_3\" class=\"msg-ref\">MSG_plans_3</a></p>\n"
expect doc("```quote\nhi\n```") == "<pre><code class=\"language-quote\">hi\n</code></pre>\n"
expect md("```quote\nhi\n```") == "<pre class=\"chat-quote\">hi\n</pre>\n"

# A link to another site stays in its tab in a document, in every form.
expect doc("[a](https://x.org) https://y.org www.z.org") == "<p><a href=\"https://x.org\">a</a> <a href=\"https://y.org\">https://y.org</a> <a href=\"http://www.z.org\">www.z.org</a></p>\n"
expect md("[a](https://x.org) https://y.org www.z.org") == "<p><a href=\"https://x.org\" target=\"_blank\" rel=\"noopener\">a</a> <a href=\"https://y.org\" target=\"_blank\" rel=\"noopener\">https://y.org</a> <a href=\"http://www.z.org\" target=\"_blank\" rel=\"noopener\">www.z.org</a></p>\n"
expect doc("[a MSG_x_1](https://y.org)") == "<p><a href=\"https://y.org\">a MSG_x_1</a></p>\n"
expect doc("![b](https://x.org/i.png)") == "<p><a href=\"https://x.org/i.png\">b</a></p>\n"
expect md("![b](https://x.org/i.png)") == "<p><a href=\"https://x.org/i.png\" target=\"_blank\" rel=\"noopener\">b</a></p>\n"
expect doc("[js](javascript:alert(1))") == "<p>[js](javascript:alert(1))</p>\n"

# Tables and nested lists are the chat's, in a document too.
expect doc("| a | b |\n| - | :-: |\n| c | `d` |\n") == md("| a | b |\n| - | :-: |\n| c | `d` |\n")
expect doc("- a\n  - b\n\n    ```roc\n    c\n    ```\n- d\n") == md("- a\n  - b\n\n    ```roc\n    c\n    ```\n- d\n")

# A newline is a space, and raw HTML is escaped, media and all.
expect doc("a\nb") == "<p>a b</p>\n"
expect md("a\nb") == "<p>a<br>\nb</p>\n"
expect doc("<div>x</div>") == "<p>&lt;div&gt;x&lt;/div&gt;</p>\n"
expect doc("<video src=\"/user_uploads/a.mp4\"></video>") == "<p>&lt;video src=&quot;/user_uploads/a.mp4&quot;&gt;&lt;/video&gt;</p>\n"
expect doc("<img src=\"/user_uploads/a.png\">") == "&lt;img src=&quot;/user_uploads/a.png&quot;&gt;"
expect md("<img src=\"/user_uploads/a.png\">") == "<img src=\"/user_uploads/a.png\">"

# A document's headings have ids, wherever they stand; a chat's have none.
expect doc("## The *sky*") == "<h2 id=\"the-sky\">The <em>sky</em></h2>\n"
expect doc("## What's a sighting?") == "<h2 id=\"whats-a-sighting\">What&#39;s a sighting?</h2>\n"
expect md("## The *sky*") == "<h2>The <em>sky</em></h2>\n"
expect Md.render_document(
	"# A\n\n> ## A\n\n- ## `A`\n".to_utf8(),
	{ fence: widgets, images: AsLinks },
).headings == [
	{
		level: 1,
		id: "a".to_utf8(),
		text: "A".to_utf8(),
	},
	{
		level: 2,
		id: "a-2".to_utf8(),
		text: "A".to_utf8(),
	},
	{
		level: 2,
		id: "a-3".to_utf8(),
		text: "A".to_utf8(),
	},
]
# A heading in a code block is code, and a hook's own stay as the hook wrote them.
expect Md.render_document(
	"```\n## no\n```".to_utf8(),
	{ fence: widgets, images: AsLinks },
).headings == []
expect Md.render_document(
	"    ## no\n\n    <h2 id=\"\">x</h2>".to_utf8(),
	{ fence: widgets, images: AsLinks },
).headings == []
expect Md.render_document(
	"<h2 id=\"\">x</h2>\n\na <h2 id=\"\">b</h2>".to_utf8(),
	{ fence: widgets, images: AsLinks },
).headings == []
expect doc("```heading\n```\n# mine") == "<h2>mine</h2>\n<h2 id=\"x\">too</h2>\n<h1 id=\"mine\">mine</h1>\n"

# Rules, wherever a block may stand. A chat reads each of these as it always has.
expect doc("---") == "<hr>\n"
expect doc("a\n\n---\n\nb") == "<p>a</p>\n<hr>\n<p>b</p>\n"
expect doc("***\n___\n- - -") == "<hr>\n<hr>\n<hr>\n"
expect doc("--") == "<p>--</p>\n"
expect doc("--- x") == "<p>--- x</p>\n"
expect md("---") == "<p>---</p>\n"
expect md("a\n\n---\n\nb") == "<p>a</p>\n<p>---</p>\n<p>b</p>\n"
expect md("***") == "<p>***</p>\n"
expect md("___") == "<p>___</p>\n"
expect md("- - -") == "<ul>\n<li>\n<ul>\n<li>\n<ul>\n<li></li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n"
expect Str.from_utf8(Md.render_trusted_reflow("a\n---".to_utf8(), chat)) == Ok("<p>a ---</p>\n")

# A rule ends a paragraph, as the dialect has no setext heading to read it as.
expect doc("a\n---\nb") == "<p>a</p>\n<hr>\n<p>b</p>\n"
expect md("a\n---\nb") == "<p>a<br>\n---<br>\nb</p>\n"
# A rule ends a list, a quote's lazy lines and a table.
expect doc("- a\n---\n- b") == "<ul>\n<li>a</li>\n</ul>\n<hr>\n<ul>\n<li>b</li>\n</ul>\n"
expect doc("- a\n- - -\n- b") == "<ul>\n<li>a</li>\n</ul>\n<hr>\n<ul>\n<li>b</li>\n</ul>\n"
expect doc("> a\n---") == "<blockquote>\n<p>a</p>\n</blockquote>\n<hr>\n"
expect doc("| a |\n| - |\n| b |\n---") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n<hr>\n"
expect md("- a\n---") == "<ul>\n<li>a<br>\n---</li>\n</ul>\n"
expect md("> a\n---") == "<blockquote>\n<p>a<br>\n---</p>\n</blockquote>\n"
expect md("| a |\n| - |\n| b |\n---") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n<tr>\n<td>---</td>\n</tr>\n</tbody>\n</table>\n"
# A rule stands inside a list item and a quote, and is code in a fence.
expect doc("- ***\n- b") == "<ul>\n<li>\n<hr>\n</li>\n<li>b</li>\n</ul>\n"
# With every mark the same, the whole line is one rule, not an item.
expect doc("- ---") == "<hr>\n"
expect doc("- a\n\n  ---\n") == "<ul>\n<li>\n<p>a</p>\n<hr>\n</li>\n</ul>\n"
expect doc("> ---") == "<blockquote>\n<hr>\n</blockquote>\n"
expect doc("```\n---\n```") == "<pre><code>---\n</code></pre>\n"
# Only a row with a pipe is a table's delimiter.
expect doc("a | b\n--- | ---") == "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n</table>\n"

# Indented code, and a chat's reading of the same lines.
expect doc("    a<b") == "<pre><code>a&lt;b\n</code></pre>\n"
expect doc("\ta") == "<pre><code>a\n</code></pre>\n"
expect doc("      a\n    b") == "<pre><code>  a\nb\n</code></pre>\n"
expect doc("   a") == "<p>a</p>\n"
expect md("    a<b") == "<p>a&lt;b</p>\n"
expect md("\ta") == "<p>a</p>\n"
expect md("x\n\n    a\n    b") == "<p>x</p>\n<p>a<br>\nb</p>\n"
# Nothing in the block is markup, and the hook isn't asked.
expect doc("    **a** [b](/c)\n    ---\n    - d\n    ```widget sky") == "<pre><code>**a** [b](/c)\n---\n- d\n```widget sky\n</code></pre>\n"
# A blank line inside a block stays, and those around it are not its own.
expect doc("    a\n\n\n    b") == "<pre><code>a\n\n\nb\n</code></pre>\n"
expect doc("    a\n   \n    b") == "<pre><code>a\n\nb\n</code></pre>\n"
expect doc("\n    a\n\n\nb") == "<pre><code>a\n</code></pre>\n<p>b</p>\n"
expect doc("    a\n\n") == "<pre><code>a\n</code></pre>\n"
# A line with less indent ends the block, blank line or not.
expect doc("    a\nb") == "<pre><code>a\n</code></pre>\n<p>b</p>\n"
expect doc("    a\n   b") == "<pre><code>a\n</code></pre>\n<p>b</p>\n"
# Indented text just after a paragraph stays that paragraph, at any depth of
# indent. After a blank line it is code.
expect doc("a\n    b") == "<p>a b</p>\n"
expect doc("a\n        b\n    c") == "<p>a b c</p>\n"
expect doc("a\n\n    b") == "<p>a</p>\n<pre><code>b\n</code></pre>\n"
# After a block that isn't a paragraph, it is code at once.
expect doc("# a\n    b") == "<h1 id=\"a\">a</h1>\n<pre><code>b\n</code></pre>\n"
expect doc("---\n    b") == "<hr>\n<pre><code>b\n</code></pre>\n"
expect doc("```\na\n```\n    b") == "<pre><code>a\n</code></pre>\n<pre><code>b\n</code></pre>\n"

# In a list, four columns past the item's content are code, and less is the
# item's own text. Each depth counts from its own item. A blank line in a nested
# item loosens the items around it too, as it does in a chat.
expect doc("- a\n\n      b") == "<ul>\n<li>\n<p>a</p>\n<pre><code>b\n</code></pre>\n</li>\n</ul>\n"
expect doc("- a\n\n    b") == "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n"
expect doc("- a\n  - b\n\n        c") == "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>\n<p>b</p>\n<pre><code>c\n</code></pre>\n</li>\n</ul>\n</li>\n</ul>\n"
expect doc("- a\n  - b\n\n      c") == "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n</ul>\n</li>\n</ul>\n"
expect doc("- a\n  - b\n    - c\n\n          d") == "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>\n<p>b</p>\n<ul>\n<li>\n<p>c</p>\n<pre><code>d\n</code></pre>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n"
expect doc("- a\n  - b\n    - c\n\n        d") == "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>\n<p>b</p>\n<ul>\n<li>\n<p>c</p>\n<p>d</p>\n</li>\n</ul>\n</li>\n</ul>\n</li>\n</ul>\n"
expect doc("1. a\n\n       b") == "<ol>\n<li>\n<p>a</p>\n<pre><code>b\n</code></pre>\n</li>\n</ol>\n"
expect doc("1. a\n\n      b") == "<ol>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ol>\n"
# Directly under an item's text it continues the paragraph, at every depth.
expect doc("- a\n      b") == "<ul>\n<li>a b</li>\n</ul>\n"
expect doc("- a\n  - b\n          c") == "<ul>\n<li>a\n<ul>\n<li>b c</li>\n</ul>\n</li>\n</ul>\n"
# A blank line inside a block in an item stays, and the list goes on after it.
expect doc("- a\n\n      b\n\n      c\n\n- d") == "<ul>\n<li>\n<p>a</p>\n<pre><code>b\n\nc\n</code></pre>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n"
# An item may open with code, and then it stands on a line of its own.
expect doc("-     a\n- b") == "<ul>\n<li>\n<pre><code>a\n</code></pre>\n</li>\n<li>b</li>\n</ul>\n"
# Under a list, text at the left margin ends it, and code after that is the page's.
expect doc("- a\n\nb\n\n    c") == "<ul>\n<li>a</li>\n</ul>\n<p>b</p>\n<pre><code>c\n</code></pre>\n"
# A chat's list keeps the same lines as text.
expect md("- a\n\n      b") == "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n"
expect md("-     a\n- b") == "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n"

# In a quote, code ends at the quote's end, and a lazy line is only a paragraph's.
expect doc(">     a\n>     b") == "<blockquote>\n<pre><code>a\nb\n</code></pre>\n</blockquote>\n"
expect doc(">     a\nb") == "<blockquote>\n<pre><code>a\n</code></pre>\n</blockquote>\n<p>b</p>\n"
expect doc("> a\n>     b\nc") == "<blockquote>\n<p>a b c</p>\n</blockquote>\n"
expect md(">     a\nb") == "<blockquote>\n<p>a<br>\nb</p>\n</blockquote>\n"

# `Shown` makes an image of any src a browser wouldn't run. `AsLinks` keeps the
# chat's answer, and neither reaches a chat, whose rule is its uploads.
expect page_with_images("![a *b*](c.png)") == "<p><img src=\"c.png\" alt=\"a b\"></p>\n"
expect page_with_images("![a](c.png \"t\")") == "<p><img src=\"c.png\" alt=\"a\" title=\"t\"></p>\n"
expect page_with_images("![a](https://x.org/i.png)") == "<p><img src=\"https://x.org/i.png\" alt=\"a\"></p>\n"
expect page_with_images("![a](/user_uploads/i.png)") == "<p><img src=\"/user_uploads/i.png\" alt=\"a\"></p>\n"
expect page_with_images("![a \"q\"](c\".png)") == "<p><img src=\"c&quot;.png\" alt=\"a &quot;q&quot;\"></p>\n"
expect page_with_images("![a](javascript:alert(1))") == "<p>![a](javascript:alert(1))</p>\n"
expect page_with_images("![a](data:text/html,x)") == "<p>![a](data:text/html,x)</p>\n"
expect page_with_images("![a](c.png bad)") == "<p>!<a href=\"c.png bad\">a</a></p>\n"
expect page_with_images("<img src=\"c.png\">") == "&lt;img src=&quot;c.png&quot;&gt;"
expect page_with_images("<video src=\"c.mp4\"></video>") == "<p>&lt;video src=&quot;c.mp4&quot;&gt;&lt;/video&gt;</p>\n"
expect doc("![a](c.png)") == "<p><a href=\"c.png\">a</a></p>\n"
expect doc("![a](/user_uploads/i.png)") == "<p><a href=\"/user_uploads/i.png\">a</a></p>\n"
expect doc("![a](javascript:alert(1))") == "<p>![a](javascript:alert(1))</p>\n"
expect md("![a](c.png)") == "<p><a href=\"c.png\">a</a></p>\n"
expect md("![a](/other/i.png)") == "<p><a href=\"/other/i.png\">a</a></p>\n"
expect md("![a](https://x.org/i.png)") == "<p><a href=\"https://x.org/i.png\" target=\"_blank\" rel=\"noopener\">a</a></p>\n"
expect md("![a](/user_uploads/i.png)") == "<p><img src=\"/user_uploads/i.png\" alt=\"a\"></p>\n"

# An angle-bracket URL is a link in a document, on a line of its own too.
expect doc("see <http://a.org/x?y=1&z=2>, now") == "<p>see <a href=\"http://a.org/x?y=1&amp;z=2\">http://a.org/x?y=1&amp;z=2</a>, now</p>\n"
expect doc("<https://a.org/x>") == "<p><a href=\"https://a.org/x\">https://a.org/x</a></p>\n"
expect doc("  <https://a.org/x>  ") == "<p><a href=\"https://a.org/x\">https://a.org/x</a></p>\n"
expect doc("<HTTP://A.org>") == "<p><a href=\"HTTP://A.org\">HTTP://A.org</a></p>\n"
expect doc("<http://localhost:9100/a_b_c>") == "<p><a href=\"http://localhost:9100/a_b_c\">http://localhost:9100/a_b_c</a></p>\n"
expect doc("<http://a.org> and <http://b.org>") == "<p><a href=\"http://a.org\">http://a.org</a> and <a href=\"http://b.org\">http://b.org</a></p>\n"
expect doc("- <http://a.org>\n\n> <http://b.org>") == "<ul>\n<li><a href=\"http://a.org\">http://a.org</a></li>\n</ul>\n<blockquote>\n<p><a href=\"http://b.org\">http://b.org</a></p>\n</blockquote>\n"
# Anything else in brackets is the text it was.
expect doc("a <http://a b> c") == "<p>a &lt;http://a b&gt; c</p>\n"
expect doc("a <http://> c") == "<p>a &lt;http://&gt; c</p>\n"
expect doc("a <http://a.org c") == "<p>a &lt;http://a.org c</p>\n"
expect doc("a <ftp://a.org> c") == "<p>a &lt;ftp://a.org&gt; c</p>\n"
expect doc("a <javascript:alert(1)> c") == "<p>a &lt;javascript:alert(1)&gt; c</p>\n"
expect doc("a <name's place> c") == "<p>a &lt;name&#39;s place&gt; c</p>\n"
expect doc("<div>") == "&lt;div&gt;"
expect doc("a \\<http://a.org> c") == "<p>a &lt;http://a.org&gt; c</p>\n"
expect doc("`<http://a.org>`") == "<p><code>&lt;http://a.org&gt;</code></p>\n"
# A chat keeps these as text, and a line of its own as an HTML block.
expect md("see <http://a.org/x> now") == "<p>see &lt;http://a.org/x&gt; now</p>\n"
expect md("<http://a.org>") == "&lt;http://a.org&gt;"

# An email is text in a document, however it stands, and a link in a chat.
expect doc("mail a.b@c.d now") == "<p>mail a.b@c.d now</p>\n"
expect doc("red@red.R0 *red@red.R1*") == "<p>red@red.R0 <em>red@red.R1</em></p>\n"
expect doc("| a@b.c |\n| - |") == "<table>\n<thead>\n<tr>\n<th>a@b.c</th>\n</tr>\n</thead>\n</table>\n"
expect doc("[a](mailto:b@c.d)") == "<p><a href=\"mailto:b@c.d\">a</a></p>\n"
expect md("mail a.b@c.d now") == "<p>mail <a href=\"mailto:a.b@c.d\">a.b@c.d</a> now</p>\n"
expect Str.from_utf8(
	Md.render_trusted_reflow("a.b@c.d".to_utf8(), chat),
) == Ok("<p><a href=\"mailto:a.b@c.d\">a.b@c.d</a></p>\n")

# A tab after a marker is the indent it reaches, in a document. A chat counts it
# as one space, as ever.
expect doc("-\tfoo") == "<ul>\n<li>foo</li>\n</ul>\n"
expect doc("1.\tfoo") == "<ol>\n<li>foo</li>\n</ol>\n"
expect doc("-\t\tfoo") == "<ul>\n<li>\n<pre><code>  foo\n</code></pre>\n</li>\n</ul>\n"
expect doc("-\t") == "<ul>\n<li></li>\n</ul>\n"
expect doc("a\n-\t") == "<p>a -</p>\n"
expect md("-\tfoo") == "<ul>\n<li>foo</li>\n</ul>\n"
expect md("1.\tfoo") == "<ol>\n<li>foo</li>\n</ol>\n"

# A tab in an item's indent counts its columns, in a document, so the item goes
# on and a list nests. A chat counts spaces, so the same lines leave the item.
expect doc("- a\n\n\tb") == "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>\n"
expect doc("- a\n\n\t\tb") == "<ul>\n<li>\n<p>a</p>\n<pre><code>  b\n</code></pre>\n</li>\n</ul>\n"
expect doc("- a\n\t- b") == "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n"
expect doc("1.\ta\n\n\tb\n\n\t\tc") == "<ol>\n<li>\n<p>a</p>\n<p>b</p>\n<pre><code>c\n</code></pre>\n</li>\n</ol>\n"
expect md("- a\n\n\tb") == "<ul>\n<li>a</li>\n</ul>\n<p>b</p>\n"
expect md("- a\n\t- b") == "<ul>\n<li>a<br>\n- b</li>\n</ul>\n"
# Tabs past the item's indent are a fence's own.
expect doc("- ```\n  \tx\n  ```") == "<ul>\n<li>\n<pre><code>\tx\n</code></pre>\n</li>\n</ul>\n"

# A tab after a quote's `>` is its space and then indent, in a document.
expect doc(">\tfoo") == "<blockquote>\n<p>foo</p>\n</blockquote>\n"
expect doc(">\t\tfoo") == "<blockquote>\n<pre><code>  foo\n</code></pre>\n</blockquote>\n"
expect md(">\tfoo") == "<blockquote>\n<p>foo</p>\n</blockquote>\n"
expect md(">\t\tfoo") == "<blockquote>\n<p>foo</p>\n</blockquote>\n"

# A document's row keeps every cell, even past the header. GFM and a chat cut
# them, so a `|` inside a link costs a chat's reader the rest of the row.
expect doc("| a |\n| :-: |\n| b | c |") == "<table>\n<thead>\n<tr>\n<th align=\"center\">a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"center\">b</td>\n<td>c</td>\n</tr>\n</tbody>\n</table>\n"
expect doc("| a | b |\n| - | - |\n| c |") == md("| a | b |\n| - | - |\n| c |")
expect md("| a |\n| - |\n| b | c |") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n"
# Indented code ends a document's table, and is a row of a chat's.
expect doc("| a |\n| - |\n    b") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n</table>\n<pre><code>b\n</code></pre>\n"
expect md("| a |\n| - |\n    b") == "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>b</td>\n</tr>\n</tbody>\n</table>\n"

# A document's label ends at its balancing `]`, so a link may wrap an image. An
# image that would be a link is its alt there, as an `<a>` can't hold an `<a>`.
expect page_with_images("[![a](i.png)](/x)") == "<p><a href=\"/x\"><img src=\"i.png\" alt=\"a\"></a></p>\n"
expect doc("[![a](i.png)](/x)") == "<p><a href=\"/x\">a</a></p>\n"
expect md("[![a](i.png)](/x)") == "<p><a href=\"i.png\">![a</a>](/x)</p>\n"
expect doc("[a\\]b](c) [a\\[b](c)") == "<p><a href=\"c\">a]b</a> <a href=\"c\">a[b</a></p>\n"
expect doc("[a[b](c)") == "<p>[a<a href=\"c\">b</a></p>\n"
expect doc("[a]b](c)") == "<p>[a]b](c)</p>\n"
# Nothing in a document's label becomes a second link.
expect doc("[https://x.org](/y)") == "<p><a href=\"/y\">https://x.org</a></p>\n"
expect doc("[<http://x.org>](/y)") == "<p><a href=\"/y\">&lt;http://x.org&gt;</a></p>\n"
expect doc("[[a](b)](c)") == "<p><a href=\"c\">[a](b)</a></p>\n"
expect md("[https://x.org](/y)") == "<p><a href=\"/y\"><a href=\"https://x.org\" target=\"_blank\" rel=\"noopener\">https://x.org</a></a></p>\n"
# An image's alt reads neither links nor images, however the brackets nest.
expect page_with_images("![![a](b)](c)") == "<p><img src=\"c\" alt=\"![a](b)\"></p>\n"
expect page_with_images("[![![a](b)](c)](d)") == "<p><a href=\"d\"><img src=\"c\" alt=\"![a](b)\"></a></p>\n"
# What a browser would run stays source, inside a label too.
expect page_with_images("[![a](javascript:x)](/y)") == "<p><a href=\"/y\">![a](javascript:x)</a></p>\n"
expect page_with_images("[a](/y)[b](javascript:x)") == "<p><a href=\"/y\">a</a>[b](javascript:x)</p>\n"

# A document's link reads a title and `<a b>`, as its image does. A chat's reads
# neither, so its href holds them.
expect doc("[a](/b \"t>\")") == "<p><a href=\"/b\" title=\"t&gt;\">a</a></p>\n"
expect doc("[a](<b c>)") == "<p><a href=\"b c\">a</a></p>\n"
expect doc("[a](<b c> 't')") == "<p><a href=\"b c\" title=\"t\">a</a></p>\n"
expect doc("[a](b c)") == "<p><a href=\"b c\">a</a></p>\n"
expect doc("[a](<b)") == "<p><a href=\"&lt;b\">a</a></p>\n"
expect doc("![a](c.png \"t\")") == "<p><a href=\"c.png\" title=\"t\">a</a></p>\n"
expect page_with_images("![a](<b c.png> 't')") == "<p><img src=\"b c.png\" alt=\"a\" title=\"t\"></p>\n"
expect md("[a](/b \"t\")") == "<p><a href=\"/b &quot;t&quot;\">a</a></p>\n"
expect md("[a](<b c>)") == "<p><a href=\"&lt;b c&gt;\">a</a></p>\n"
# Brackets hide nothing from the safety rule.
expect doc("[a](<javascript:x>)") == "<p>[a](&lt;javascript:x&gt;)</p>\n"
expect doc("[a]( <JavaScript:x> \"t\")") == "<p>[a]( &lt;JavaScript:x&gt; &quot;t&quot;)</p>\n"
expect page_with_images("![a](<java\tscript:x>)") == "<p>![a](&lt;java\tscript:x&gt;)</p>\n"

# A document's `\r\n` is a line's end to every block and to the hook.
expect doc("-\r\n- b\r\n") == "<ul>\n<li></li>\n<li>b</li>\n</ul>\n"
expect doc("# h #\r\n```dot\r\na\r\n```\r\n") == "<h1 id=\"h\">h</h1>\n<svg>a\n</svg>\n"
expect md("-\r\n- b\r\n") == "<p>-</p>\n<ul>\n<li>b</li>\n</ul>\n"

# A heading a hook wrote stays as it wrote it, even with an empty id.
expect doc("```raw\n```\n# b") == "<h2 id=\"\">x</h2>\n<h1 id=\"b\">b</h1>\n"
expect Md.render_document(
	"```raw\n```\n# b".to_utf8(),
	{ fence: widgets, images: AsLinks },
).headings == [
	{
		level: 1,
		id: "b".to_utf8(),
		text: "b".to_utf8(),
	},
]

# The chat's answers for a text with every feature here, in each mode a
# chat has.
every_feature : Str
every_feature = "# a MSG_x_1\n\nb\nc [d](https://x.org) https://y.org\n\n```quote\ne\n```\n\n```dot\nf\n```\n\n| g |\n| - |\n| h |\n\n<video src=\"/user_uploads/i.mp4\"></video>\n"

every_feature_html : Str -> Str
every_feature_html = |line_join| "<h1>a <a href=\"#msg-x_1\" class=\"msg-ref\">MSG_x_1</a></h1>\n<p>b${line_join}c <a href=\"https://x.org\" target=\"_blank\" rel=\"noopener\">d</a> <a href=\"https://y.org\" target=\"_blank\" rel=\"noopener\">https://y.org</a></p>\n<pre class=\"chat-quote\">e\n</pre>\n<pre><code class=\"language-dot\">f\n</code></pre>\n<table>\n<thead>\n<tr>\n<th>g</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>h</td>\n</tr>\n</tbody>\n</table>\n<p><video controls preload=\"metadata\" src=\"/user_uploads/i.mp4\"></video></p>\n"

expect md(every_feature) == every_feature_html("<br>\n")
expect Str.from_utf8(
	Md.render_trusted(every_feature.to_utf8(), chat),
) == Ok(every_feature_html("<br>\n"))
expect Str.from_utf8(
	Md.render_trusted_reflow(every_feature.to_utf8(), chat),
) == Ok(every_feature_html(" "))
expect Md.hostility(every_feature.to_utf8(), chat) == Renderable
