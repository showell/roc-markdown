// **DOES THE PAGE RUN?** (run by playground/check.zig): the built folder's
// index.html and app.js, run as a browser would against a stand-in DOM (a
// small one, after chat-client's tools/fakedom.mjs) and the real md.wasm,
// with `fetch` reading the folder. It checks what a user does: the page
// starts on the first example, choosing each example loads its source and
// caption and renders it (a hostile message, in chat mode, refused as the
// chat refuses it), typing renders after the pause, a mode switch
// re-renders, the HTML-source toggle shows the html as text, and the page
// fetches nothing outside its folder.
//
//   node playground/page_check.mjs <the built folder>
//
// It prints `== page: ...` and exits 0, or names what failed and exits 1.

import { readFileSync, existsSync } from "node:fs";
import { pathToFileURL } from "node:url";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: page_check.mjs <the built playground folder>");
  process.exit(2);
}
const fails = [];
const check = (ok, what) => { if (!ok) fails.push(what); };

// ── the folder: everything the page names is in it, nothing from elsewhere ──
const page = readFileSync(`${dir}/index.html`, "utf8");
const named = [...page.matchAll(/(?:src|href)="([^"]+)"/g)].map((m) => m[1]);
for (const n of named) {
  if (/^https?:/.test(n)) {
    // A link a reader follows is fine; a script, a style or an image is not.
    // An <a> element's href, wherever the attribute sits in its tag.
    const asLink = new RegExp(`<a\\s[^>]*href="${n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"`);
    check(asLink.test(page), `the page loads ${n} from elsewhere`);
  } else {
    check(existsSync(`${dir}/${n}`), `the page names ${n}, which is not in the folder`);
  }
}
for (const f of ["app.js", "md_wasm.js", "style.css"]) {
  check(!/(?:import|fetch|url)\s*\(?\s*["']?https?:/i.test(readFileSync(`${dir}/${f}`, "utf8")), `${f} reaches outside the folder`);
}

// ── a stand-in DOM: the elements index.html declares, by id ──
class El {
  constructor(tag, attrs = {}) {
    this.tagName = tag.toUpperCase();
    this.attrs = attrs;
    this.children = [];
    this.listeners = {};
    this.textContent = "";
    this.className = "";
    this.hidden = "hidden" in attrs;
    this.value = attrs.value ?? "";
    this.checked = "checked" in attrs;
    this._html = null;
  }
  set innerHTML(h) { this._html = h; }
  get innerHTML() { return this._html ?? this.textContent; }
  appendChild(c) { this.children.push(c); return c; }
  addEventListener(type, f) { (this.listeners[type] ??= []).push(f); }
  fire(type) { for (const f of this.listeners[type] ?? []) f({ type, target: this }); }
}
class Select extends El {
  get value() { return this._value ?? (this.children[0]?.value ?? ""); }
  set value(v) { this._value = v; }
}
const byId = {};
const radios = [];
for (const m of page.matchAll(/<(\w+)([^>]*)>/g)) {
  const [, tag, rest] = m;
  const attrs = {};
  for (const a of rest.matchAll(/([\w-]+)(?:="([^"]*)")?/g)) attrs[a[1]] = a[2] ?? "";
  const el = tag === "select" ? new Select(tag, attrs) : new El(tag, attrs);
  if (attrs.id) byId[attrs.id] = el;
  if (tag === "input" && attrs.type === "radio") radios.push(el);
}
const document = {
  getElementById: (id) => byId[id] ?? null,
  createElement: (tag) => new El(tag),
  querySelectorAll: (sel) => {
    if (sel !== 'input[name="mode"]') throw new Error(`the stand-in DOM cannot select ${sel}`);
    return radios;
  },
};
// A radio checked unchecks the others, as a browser does.
const pick = (value) => {
  for (const r of radios) r.checked = r.attrs.value === value;
  radios.find((r) => r.checked).fire("change");
};
const fetched = [];
globalThis.document = document;
globalThis.fetch = async (path) => {
  fetched.push(path);
  const p = `${dir}/${path}`;
  if (/^[a-z]+:/.test(path) || path.includes("..") || !existsSync(p)) return { ok: false, status: 404 };
  const bytes = readFileSync(p);
  return {
    ok: true,
    status: 200,
    arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length),
    text: async () => bytes.toString("utf8"),
  };
};

check(/<script type="module" src="app.js"><\/script>/.test(page), "the page does not load app.js as a module");
await import(pathToFileURL(`${dir}/app.js`).href);
const app = await globalThis.playground;

// The renderer itself, for what the page should show.
const { load } = await import(pathToFileURL(`${dir}/md_wasm.js`).href);
const md = await load(readFileSync(`${dir}/md.wasm`));

const $ = (id) => byId[id];
const shows = (src, mode, what) => {
  const want = md.answer(src, mode);
  // The chat refuses a hostile message: chat mode shows the refusal, in the
  // chat's own words, and no render; every other message and mode, the render.
  const refused = mode === "chat" && want.hostile !== "";
  const shown = refused ? "" : want.html;
  check($("refusal").hidden === !refused, `${what}: the refusal is ${refused ? "hidden" : "shown"} in ${mode} mode`);
  check(!refused || $("refusal").textContent.includes(`"${want.hostile}"`), `${what}: the refusal is not in the chat's words`);
  check($("preview").innerHTML === shown, `${what}: the preview is not the ${mode} ${refused ? "refusal" : "render"}`);
  check($("html").textContent === shown, `${what}: the HTML source is not the ${mode} ${refused ? "refusal" : "render"}`);
  check($("units").textContent === String(want.workUnits), `${what}: the work units shown are not the render's`);
  check($("hostility").textContent.startsWith(want.hostile === "" ? "Renderable" : "TooMuchFormatting"), `${what}: the hostility shown is not the render's`);
};

const examples = readFileSync(`${dir}/examples.jsonl`, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
check(examples.length >= 5, `only ${examples.length} examples`);
check($("example").children.filter((o) => o.value !== "").map((o) => o.value).join() === examples.map((e) => e.id).join(), "the menu is not the examples");

// It starts on the first example.
check($("source").value === examples[0].md, "the page did not start on the first example");
check($("caption").textContent === examples[0].caption, "the first example's caption is not shown");
shows(examples[0].md, "chat", "at start");

// Choosing each example.
for (const ex of [...examples].reverse()) {
  $("example").value = ex.id;
  $("example").fire("change");
  check($("source").value === ex.md, `${ex.id}: choosing it did not load its source`);
  check($("caption").textContent === ex.caption, `${ex.id}: its caption is not shown`);
  check(!$("preview").innerHTML.includes("<script"), `${ex.id}: the preview holds a script tag`);
  shows(ex.md, "chat", ex.id);
}

// Each mode, on every example and a hostile message (the budget is what
// tells chat from trusted, the wraps trusted from reflow): each two modes
// must be told apart by some source, so a page showing the wrong one is red.
const hostile = "|a".repeat(200) + "|\n" + "|-".repeat(200) + "|\n" + "x\n".repeat(200);
const sources = [...examples.map((e) => e.md), hostile];
// The canned `hostile` example is what it says: the chat refuses it, and a
// trusted mode renders it.
const canned = examples.find((e) => e.id === "hostile");
check(canned !== undefined, "no canned `hostile` example");
if (canned) {
  check(md.answer(canned.md, "chat").hostile !== "", "the `hostile` example is renderable");
  check(md.answer(canned.md, "trusted").html.includes("Hostile markdown input gets rejected"), "the `hostile` example's trusted render lacks its top");
}
const MODES = ["chat", "trusted", "reflow"];
for (const [i, m1] of MODES.entries()) for (const m2 of MODES.slice(i + 1)) {
  check(sources.some((s) => md.answer(s, m1).html !== md.answer(s, m2).html), `no source tells ${m1} from ${m2}`);
}
for (const mode of ["trusted", "reflow", "chat"]) {
  for (const [k, s] of sources.entries()) {
    $("source").value = s;
    pick(mode);
    shows(s, mode, `mode ${mode}, source ${k}`);
  }
}

// Typing: the preview follows after the pause, and the caption goes.
$("source").value = "# typed\n\n| a |\n|---|\n| *b* |\n";
$("source").fire("input");
await new Promise((r) => setTimeout(r, 200));
shows($("source").value, "chat", "typed");
check($("caption").textContent === "" && $("example").value === "", "typing over an example kept its caption");

// A hostile message, typed: the chat's refusal is shown.
$("source").value = hostile;
$("source").fire("input");
await new Promise((r) => setTimeout(r, 200));
shows(hostile, "chat", "hostile");
check($("hostility").className === "hostile" && $("hostility").textContent.includes("too much"), "a hostile message does not show the chat's refusal");
check(!$("refusal").hidden && $("preview").innerHTML === "", "a hostile message is rendered in chat mode, not refused");
// A trusted mode renders it all the same.
pick("trusted");
shows(hostile, "trusted", "hostile, trusted");
check($("refusal").hidden && $("preview").innerHTML !== "", "a hostile message is refused in trusted mode");
pick("chat");

// The HTML-source toggle.
$("show-source").checked = true;
$("show-source").fire("change");
check(!$("html").hidden && $("preview").hidden, "the HTML-source toggle did not show the source");
$("show-source").checked = false;
$("show-source").fire("change");
check($("html").hidden && !$("preview").hidden, "the HTML-source toggle did not hide the source again");

check(fetched.every((p) => !/^[a-z]+:/.test(p)), `the page fetched outside its folder: ${fetched.join(", ")}`);
check(app.examples.length === examples.length, "the app's examples are not the folder's");

if (fails.length) {
  for (const f of fails) console.error(`PAGEFAIL\t${f}`);
  process.exit(1);
}
console.log(`== page: starts on ${examples[0].id}; ${examples.length} examples chosen, 3 modes, typing, a hostile message and the source toggle; fetched ${fetched.join(", ")}`);
