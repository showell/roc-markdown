## **THE PLAYGROUND'S PLATFORM** (playground/platform/host.zig): one entry,
## `roc_play_answer`, that hands a message's bytes and a mode to the app and
## answers its results, each as bytes, inside a wasm32 module a page loads.
platform ""
	requires {
		answer : List(U8), U8 -> List(List(U8))
	}
	exposes []
	packages {}
	provides { "roc_play_answer": answer_for_host }
	targets: {
		inputs_dir: "targets/",
		wasm32: {
			inputs: ["host.wasm", app],
			exports: ["input", "answer", "partPtr", "partLen"],
		},
	}

answer_for_host : List(U8), U8 -> List(List(U8))
answer_for_host = |md, mode| answer(md, mode)
