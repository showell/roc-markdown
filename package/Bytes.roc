## BYTES AS ZIG'S std.mem HANDLES THEM: the searches, scans and trims the
## markdown's modules share, each in one place (`std.mem.indexOf`,
## `indexOfScalar`, `trim`), on bytes, never Str; a byte's class is Ascii's.
## Pure. The package's own: roc-chat has a Bytes of its own, and the two are
## free to differ.

Bytes := [].{

	## Where `needle` first starts in `s` (std.mem.indexOf).
	find : List(U8), { needle : List(U8) } -> Try(U64, [NotFound])
	find = |s, { needle }| find_from(s, { needle, at: 0 })

	find_byte : List(U8), { byte : U8, at : U64 } -> Try(U64, [NotFound])
	find_byte = |s, { byte: b, at: i }| match List.get(s, i) {
		Ok(c) => if c == b Ok(i) else find_byte(s, { byte: b, at: i + 1 })
		Err(_) => Err(NotFound)
	}

	## How many bytes from `i` on keep `keep`.
	count_while : List(U8), { keep : (U8 -> Bool), at : U64 } -> U64
	count_while = |s, { keep, at: i }| match List.get(s, i) {
		Ok(c) if keep(c) => count_while(s, { keep, at: i + 1 })
		_ => i
	}

	## How many bytes from the end keep `keep`.
	count_back : List(U8), (U8 -> Bool) -> U64
	count_back = |s, keep| count_back_from(s, { keep, kept: 0 })

	## `std.mem.trim(u8, s, set)`: the bytes in `set` off both ends.
	trim : List(U8), List(U8) -> List(U8)
	trim = |s, set| {
		in_set = |c| List.contains(set, c)
		front = List.drop_first(
			s,
			count_while(s, { keep: in_set, at: 0 }),
		)
		List.drop_last(
			front,
			count_back(front, in_set),
		)
	}

	## The four bytes Zig's `std.mem.trim(u8, s, " \t\r\n")` trims: not
	## `Ascii.is_whitespace`, which has VT and FF too.
	zig_spaces : List(U8)
	zig_spaces = [
		' ',
		'\t',
		'\r',
		'\n',
	]

}

find_from : List(U8), { needle : List(U8), at : U64 } -> Try(U64, [NotFound])
find_from = |s, { needle, at: i }|
	if i + List.len(needle) > List.len(s) {
		Err(NotFound)
	} else if List.get(s, i) == List.first(needle) and List.sublist(
		s,
		{ start: i, len: List.len(needle) },
	) == needle {
		Ok(i)
	} else {
		find_from(s, { needle, at: i + 1 })
	}

count_back_from : List(U8), { keep : (U8 -> Bool), kept : U64 } -> U64
count_back_from = |s, { keep, kept: n }|
	if n >= List.len(s) {
		n
	} else {
		match List.get(s, List.len(s) - 1 - n) {
			Ok(c) if keep(c) => count_back_from(s, { keep, kept: n + 1 })
			_ => n
		}
	}
