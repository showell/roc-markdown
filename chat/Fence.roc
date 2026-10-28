## **A MARKDOWN FENCE AS markdown_fence.zig READS IT** (metal-vmm QUEUE
## 300): where a code fence opens (its character, its length, its
## language) and where it closes; the code feed's (Feeds) and Recent's
## excerpt's. Pure.
import Bytes

Fence := [].{

	close_at : List(List(U8)), U8, U64, U64 -> U64
	close_at = |
		ls,
		char,
		count,
		j,
	| match List.get(ls, j) {
		Err(_) => j
		Ok(line) => if is_close(
			line,
			char,
			count,
		) j else close_at(
			ls,
			char,
			count,
			j + 1,
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
			Bytes.leading(
				line,
				' ',
				0,
			),
			4,
		)
		match List.get(line, indent) {
			Err(_) => Err(NotAFence)
			Ok(f) =>
				if indent >= 4 or (f != '`' and f != '~') {
					Err(NotAFence)
				} else {
					count = Bytes.leading(
						List.drop_first(line, indent),
						f,
						0,
					)
					info = trim_info(List.drop_first(line, indent + count))
					if count < 3 or count > 10 or (f == '`' and List.contains(info, '`')) {
						Err(NotAFence)
					} else {
						lang = List.take_first(
							info,
							Bytes.count_while(
								info,
								|c| c != ' ' and c != '\t',
								0,
							),
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
is_close : List(U8), U8, U64 -> Bool
is_close = |
	line,
	char,
	count,
| {
	indent = U64.min(
		Bytes.leading(
			line,
			' ',
			0,
		),
		4,
	)
	if indent >= 4 {
		Bool.False
	} else {
		n = Bytes.leading(
			List.drop_first(line, indent),
			char,
			0,
		)
		n >= count and trim_info(List.drop_first(line, indent + n)) == []
	}
}

## `std.mem.trim(u8, s, " \t\r")`.
trim_info : List(U8) -> List(U8)
trim_info = |s| {
	ws = |c| c == ' ' or c == '\t' or c == '\r'
	front = List.drop_first(
		s,
		Bytes.Bytes.count_while(
			s,
			ws,
			0,
		),
	)
	List.drop_last(
		front,
		Bytes.count_back(
			front,
			ws,
			0,
		),
	)
}
