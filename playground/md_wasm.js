// **THE RENDERER'S DOOR** (md.wasm, built from playground/answer.roc on
// playground/platform/): one call, `answer(md, mode)`, the package's three
// answers for a message. The page and the test (check.mjs) both come through
// here, so the test holds the page's own seam to the judge's answers.
//
// The bytes cross through the wasm's memory: `input(len)` hands back where to
// write the message's UTF-8, `answer(len, mode)` renders it, and each answer
// is read out by `partPtr(k)` and `partLen(k)`, valid until the next call.

export const MODES = ["chat", "trusted", "reflow"];

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });

// The wasm's bytes, instantiated; its four exports wrapped.
export async function load(bytes) {
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const x = instance.exports;
  for (const name of ["memory", "input", "answer", "partPtr", "partLen"]) {
    if (!(name in x)) throw new Error(`md.wasm does not export ${name}`);
  }
  const answer = (md, mode) => {
    const m = MODES.indexOf(mode);
    if (m < 0) throw new Error(`no mode ${mode}`);
    const text = encoder.encode(md);
    const at = x.input(text.length);
    new Uint8Array(x.memory.buffer, at, text.length).set(text);
    const n = x.answer(text.length, m);
    if (n !== 3) throw new Error(`md.wasm gave ${n} answers, not 3`);
    // The memory may have grown during the call: a fresh view each read.
    const part = (k) => decoder.decode(new Uint8Array(x.memory.buffer, x.partPtr(k), x.partLen(k)));
    return { html: part(0), workUnits: Number(part(1)), hostile: part(2) };
  };
  return { answer };
}
