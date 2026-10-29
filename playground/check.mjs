// **THE PLAYGROUND'S WASM IN NODE** (run by playground/check.zig): the
// built folder's md.wasm, through the page's own door (md_wasm.js), asked
// what the page would ask. Each line of stdin is a request,
// `{"md": ..., "mode": "chat" | "trusted" | "reflow"}`; each line out is its
// answer, `{"html", "work_units", "hostile", "ms"}`. It judges nothing: the
// Zig side holds the answers to the frozen ones.
//
//   node playground/check.mjs <the built folder>

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: check.mjs <the built playground folder>");
  process.exit(2);
}
const { load } = await import(pathToFileURL(`${dir}/md_wasm.js`).href);
const md = await load(readFileSync(`${dir}/md.wasm`));

const input = readFileSync(0, "utf8");
const out = [];
for (const line of input.split("\n")) {
  if (line === "") continue;
  const req = JSON.parse(line);
  const t0 = performance.now();
  const got = md.answer(req.md, req.mode);
  const ms = performance.now() - t0;
  out.push(JSON.stringify({ html: got.html, work_units: got.workUnits, hostile: got.hostile, ms }));
}
process.stdout.write(out.join("\n") + "\n");
