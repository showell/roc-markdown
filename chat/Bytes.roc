## BYTES AS ZIG'S std.mem HANDLES THEM: the searches and splits the chat's
## pure modules share (`std.mem.splitScalar`, `splitSequence`, `indexOf`,
## `startsWith`, `lessThan`), on bytes, never Str. Pure.

Bytes := [].{
	leading : List(U8), U8, U64 -> U64
	leading = |
		l,
		c,
		n,
	| match List.get(l, n) {
		Ok(x) if x == c => leading(
			l,
			c,
			n + 1,
		)
		_ => n
	}

	join_lines : List(List(U8)) -> List(U8)
	join_lines = |lines| List.join(List.intersperse(lines, ['\n']))

	## The bytes before and after the first `needle`.
	cut_seq : List(U8), List(U8) -> Try((List(U8), List(U8)), [NotFound])
	cut_seq = |s, needle| {
		i = find(
			s,
			needle,
			0,
		)?
		Ok((List.take_first(s, i), List.drop_first(s, i + List.len(needle))))
	}

	find : List(U8), List(U8), U64 -> Try(U64, [NotFound])
	find = |
		s,
		needle,
		i,
	|
		if i + List.len(needle) > List.len(s) {
			Err(NotFound)
		} else if List.get(s, i) == List.first(needle) and List.sublist(
			s,
			{ start: i, len: List.len(needle) },
		) == needle {
			Ok(i)
		} else {
			find(
				s,
				needle,
				i + 1,
			)
		}

	## The bytes after `prefix`, when `l` starts with it: no length is
	## written beside the literal it belongs to.
	strip_prefix : List(U8), List(U8) -> Try(List(U8), [NoMatch])
	strip_prefix = |l, prefix| if List.starts_with(l, prefix) Ok(
		List.drop_first(
			l,
			List.len(prefix),
		),
	) else Err(NoMatch)

	## std.mem.order of bytes: byte by byte, a prefix first.
	compare : List(U8),
	List(U8) -> [
		Before,
		Same,
		After,
	]
	compare = |a, b| match (a, b) {
		([x, .. as ra], [y, .. as rb]) => if x < y Before else if x > y After else compare(ra, rb)
		([], []) => Same
		([], _) => Before
		_ => After
	}

	## **A BYTE'S NEXT PLACE, REMEMBERED** (metal-vmm QUEUE 268): what one
	## search found (`At`), or that there is none (`Never`), answers every
	## later search from a place at or before it, so a scan that searches
	## from each of many openers (`<img ` after `<img `, `![` after `![`)
	## costs one pass of a message, not one per opener. `from` must not go
	## back between calls that share one.
	Seen : [
		Unknown,
		At(U64),
		Never,
	]

	find_seen : List(U8), U8, U64, Seen -> (Try(U64, [NotFound]), Seen)
	find_seen = |
		s,
		b,
		from,
		seen,
	|
		match seen {
			At(k) if k >= from => (Ok(k), seen)
			Never => (Err(NotFound), Never)
			_ =>
				match find_byte(
					s,
					b,
					from,
				) {
					Ok(k) => (Ok(k), At(k))
					Err(NotFound) => (Err(NotFound), Never)
				}
		}

	find_byte : List(U8), U8, U64 -> Try(U64, [NotFound])
	find_byte = |
		s,
		b,
		i,
	| match List.get(s, i) {
		Ok(c) => if c == b Ok(i) else find_byte(
			s,
			b,
			i + 1,
		)
		Err(_) => Err(NotFound)
	}

	lower : List(U8) -> List(U8)
	lower = |s| List.map(s, |c| if c >= 'A' and c <= 'Z' c - 'A' + 'a' else c)

	## A space, tab, newline, CR, form feed (12) or vertical tab (11): Roc's
	## character literals have no escape for the last two.
	is_space : U8 -> Bool
	is_space = |c| c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 12 or c == 11

	## How many bytes from `i` on keep `keep`.
	count_while : List(U8), (U8 -> Bool), U64 -> U64
	count_while = |
		s,
		keep,
		i,
	| match List.get(s, i) {
		Ok(c) if keep(c) => count_while(
			s,
			keep,
			i + 1,
		)
		_ => i
	}

	## How many bytes from the end keep `keep`.
	count_back : List(U8), (U8 -> Bool), U64 -> U64
	count_back = |
		s,
		keep,
		n,
	|
		if n >= List.len(s) {
			n
		} else {
			match List.get(s, List.len(s) - 1 - n) {
				Ok(c) if keep(c) => count_back(
					s,
					keep,
					n + 1,
				)
				_ => n
			}
		}

}
