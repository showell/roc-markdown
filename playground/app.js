// **THE PLAYGROUND'S PAGE**: markdown on the left, the package's render on
// the right, as you type. The canned examples are the judge's
// (examples.jsonl, beside the page); choosing one loads its source into the
// editor, where it is yours to change.
//
// **ONLY THE RENDERER'S HTML IS INSERTED AS HTML**, into #preview: it is what
// the chat would show. Everything else the page writes (captions, the html
// source, the answers, an error) is text.

import { load } from "./md_wasm.js";

const $ = (id) => {
  const e = document.getElementById(id);
  if (!e) throw new Error(`the page has no #${id}`);
  return e;
};

// Typing renders after this pause; choosing an example or a mode, at once.
const TYPING_MS = 60;

async function fetched(path, how) {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${path}: ${r.status}`);
  return how === "bytes" ? r.arrayBuffer() : r.text();
}

function parseExamples(jsonl) {
  return jsonl.split("\n").filter((l) => l !== "").map((l) => JSON.parse(l));
}

async function main() {
  const [wasm, jsonl] = await Promise.all([fetched("md.wasm", "bytes"), fetched("examples.jsonl", "text")]);
  const md = await load(wasm);
  const examples = parseExamples(jsonl);

  const source = $("source"), preview = $("preview"), html = $("html");
  const menu = $("example"), caption = $("caption"), showSource = $("show-source");
  const units = $("units"), hostility = $("hostility"), error = $("error");
  const modes = [...document.querySelectorAll('input[name="mode"]')];

  for (const ex of examples) {
    const o = document.createElement("option");
    o.value = ex.id;
    o.textContent = ex.id;
    menu.appendChild(o);
  }
  const edited = document.createElement("option");
  edited.value = "";
  edited.textContent = "(your own)";
  menu.appendChild(edited);

  const mode = () => (modes.find((m) => m.checked) || modes[0]).value;

  function render() {
    let got;
    try {
      got = md.answer(source.value, mode());
    } catch (e) {
      preview.innerHTML = "";
      html.textContent = "";
      units.textContent = hostility.textContent = "";
      error.textContent = `the renderer failed: ${e && e.message || e}`;
      error.hidden = false;
      return;
    }
    error.hidden = true;
    preview.innerHTML = got.html;
    html.textContent = got.html;
    units.textContent = String(got.workUnits);
    hostility.textContent = got.hostile === "" ? "Renderable" : `TooMuchFormatting: the chat says "${got.hostile}"`;
    hostility.className = got.hostile === "" ? "" : "hostile";
  }

  function choose(id) {
    const ex = examples.find((e) => e.id === id);
    if (!ex) return;
    menu.value = ex.id;
    caption.textContent = ex.caption;
    source.value = ex.md;
    render();
  }

  let pending = null;
  source.addEventListener("input", () => {
    // Changed from an example: still shown, its caption no longer the text's.
    if (menu.value !== "" && examples.find((e) => e.id === menu.value)?.md !== source.value) {
      menu.value = "";
      caption.textContent = "";
    }
    clearTimeout(pending);
    pending = setTimeout(render, TYPING_MS);
  });
  menu.addEventListener("change", () => choose(menu.value));
  for (const m of modes) m.addEventListener("change", render);
  showSource.addEventListener("change", () => {
    html.hidden = !showSource.checked;
    preview.hidden = showSource.checked;
  });

  const wanted = decodeURIComponent((globalThis.location?.hash || "").slice(1));
  choose(examples.some((e) => e.id === wanted) ? wanted : examples[0].id);
  return { examples, choose, render };
}

// The page's run, as a promise a test can wait on.
globalThis.playground = main().catch((e) => {
  const el = document.getElementById("error");
  if (el) {
    el.textContent = `the playground did not start: ${e && e.message || e}`;
    el.hidden = false;
  }
  throw e;
});
