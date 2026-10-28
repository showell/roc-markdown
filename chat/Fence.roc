## **A MARKDOWN FENCE AS markdown_fence.zig READS IT** (metal-vmm QUEUE
## 300): where a code fence opens (its character, its length, its
## language) and where it closes; the code feed's (Feeds) and Recent's
## excerpt's. Pure.
import Bytes

Fence := [].{

	close_at : List(List(U8)),
	{
		char : U8,
		count : U64,
		at : U64,
	} -> U64
	close_at = |
		ls,
		{
			char,
			count,
			at: j,
		},
	| match List.get(ls, j) {
		Err(_) => j
		Ok(line) => if is_close(line, { char, count }) j else close_at(
			ls,
			{
				char,
				count,
				at: j + 1,
			},
		)
	}

	## markdown_fence `parseOpen`: up to three spaces, 3 to 10 of '`' or '~',
	## and an info string whose first word is the language (no '`' in a
	## backtick fence's).
	fence_open : List(U8) -> Try(
		{
			char : U8,
			count : U64,
			lang : List(U8),
		},
		[NotAFence],
	)
	fence_open = |line| {
		indent = U64.min(
			Bytes.count_while(line, { keep: |x| x == ' ', at: 0 }),
			4,
		)
		match List.get(line, indent) {
			Err(_) => Err(NotAFence)
			Ok(f) =>
				if indent >= 4 or (f != '`' and f != '~') {
					Err(NotAFence)
				} else {
					count = Bytes.count_while(
						List.drop_first(line, indent),
						{ keep: |x| x == f, at: 0 },
					)
					info = Bytes.trim(
						List.drop_first(line, indent + count),
						[
							' ',
							'\t',
							'\r',
						],
					)
					if count < 3 or count > 10 or (f == '`' and List.contains(info, '`')) {
						Err(NotAFence)
					} else {
						lang = List.take_first(
							info,
							Bytes.count_while(info, { keep: |c| c != ' ' and c != '\t', at: 0 }),
						)
						Ok({
							char: f,
							count,
							lang,
						})
					}
				}
		}
	}
}

## markdown_fence `isClose`: up to three spaces, at least `count` of
## `char`, then only whitespace.
is_close : List(U8), { char : U8, count : U64 } -> Bool
is_close = |line, { char, count }| {
	indent = U64.min(
		Bytes.count_while(line, { keep: |x| x == ' ', at: 0 }),
		4,
	)
	if indent >= 4 {
		Bool.False
	} else {
		n = Bytes.count_while(List.drop_first(line, indent), { keep: |x| x == char, at: 0 })
		n >= count and Bytes.trim(
			List.drop_first(line, indent + n),
			[
				' ',
				'\t',
				'\r',
			],
		) == []
	}
}
