## BYTES AS ZIG'S std.mem HANDLES THEM: the searches and splits the chat's
## pure modules share (`std.mem.splitScalar`, `splitSequence`, `indexOf`,
## `startsWith`, `lessThan`), on bytes, never Str. Pure.

Bytes := [].{
	leading : List(U8), U8, U64 -> U64
	leading = |l, c, n| match List.get(l, n) {
		Ok(x) if x == c => leading(l, c, n + 1)
		_ => n
	}

	join_lines : List(List(U8)) -> List(U8)
	join_lines = |lines| List.join(List.intersperse(lines, ['\n']))

	## std.mem.splitScalar: every piece, empty ones too, as slices.
	split_byte : List(U8), U8 -> List(List(U8))
	split_byte = |s, b| split_byte_from(s, b, 0, 0, [])

	## std.mem.splitSequence: every piece between non-overlapping matches
	## of `needle`, found left to right.
	split_seq : List(U8), List(U8) -> List(List(U8))
	split_seq = |s, needle| split_seq_from(s, needle, 0, 0, [])

	## The bytes before and after the first `needle`.
	cut_seq : List(U8), List(U8) -> Try((List(U8), List(U8)), [NotFound])
	cut_seq = |s, needle| {
		i = find(s, needle, 0)?
		Ok((List.take_first(s, i), List.drop_first(s, i + List.len(needle))))
	}

	find : List(U8), List(U8), U64 -> Try(U64, [NotFound])
	find = |s, needle, i|
		if i + List.len(needle) > List.len(s) {
			Err(NotFound)
		} else if List.get(s, i) == List.first(needle) and List.sublist(s, { start: i, len: List.len(needle) }) == needle {
			Ok(i)
		} else {
			find(s, needle, i + 1)
		}

	## The bytes after `prefix`, when `l` starts with it: no length is
	## written beside the literal it belongs to.
	strip_prefix : List(U8), List(U8) -> Try(List(U8), [NoMatch])
	strip_prefix = |l, prefix| if has_prefix(l, prefix) Ok(List.drop_first(l, List.len(prefix))) else Err(NoMatch)

	## std.mem.sort with lessThanStr: equal strings are the same bytes, so the
	## order among them cannot show.
	sort : List(List(U8)) -> List(List(U8))
	sort = |l| List.sort_with(l, compare)

	## std.mem.order of bytes: byte by byte, a prefix first.
	compare : List(U8), List(U8) -> [Before, Same, After]
	compare = |a, b| match (a, b) {
		([x, .. as ra], [y, .. as rb]) => if x < y Before else if x > y After else compare(ra, rb)
		([], []) => Same
		([], _) => Before
		_ => After
	}
}

split_byte_from : List(U8), U8, U64, U64, List(List(U8)) -> List(List(U8))
split_byte_from = |s, b, start, i, out| match List.get(s, i) {
	Err(_) => List.append(out, List.drop_first(s, start))
	Ok(c) =>
		if c == b {
			split_byte_from(s, b, i + 1, i + 1, List.append(out, List.sublist(s, { start, len: i - start })))
		} else {
			split_byte_from(s, b, start, i + 1, out)
		}
}

split_seq_from : List(U8), List(U8), U64, U64, List(List(U8)) -> List(List(U8))
split_seq_from = |s, needle, start, i, out| {
	n = List.len(needle)
	if i + n > List.len(s) {
		List.append(out, List.drop_first(s, start))
	} else if List.get(s, i) == List.first(needle) and List.sublist(s, { start: i, len: n }) == needle {
		split_seq_from(s, needle, i + n, i + n, List.append(out, List.sublist(s, { start, len: i - start })))
	} else {
		split_seq_from(s, needle, start, i + 1, out)
	}
}

has_prefix : List(U8), List(U8) -> Bool
has_prefix = |l, p| List.len(l) >= List.len(p) and List.take_first(l, List.len(p)) == p
