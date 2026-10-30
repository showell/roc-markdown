## **THE JUDGE'S PLATFORM** (judge/judge.zig): one entry, `roc_judge_answers`,
## that hands a message's bytes and the name of its corpus's uploads rule to
## the app and answers its results, each as bytes. It exists so the judge, a Zig program, can call the package; it
## is never linked into a server.
platform ""
	requires {
		answers : List(U8), List(U8) -> List(List(U8))
	}
	exposes []
	packages {}
	provides { "roc_judge_answers": answers_for_host }
	targets: {
		x64musl: {
			inputs: [app],
			output: Archive,
		},
	}

answers_for_host : List(U8), List(U8) -> List(List(U8))
answers_for_host = |md, uploads| answers(md, uploads)
