## BYTES AS ZIG'S std.mem HANDLES THEM: the searches, scans and trims the
## markdown's modules share, each in one place (`std.mem.indexOf`,
## `indexOfScalar`, `trim`), on bytes, never Str; a byte's class is Ascii's.
## Pure. The package's own: roc-chat has a Bytes of its own, and the two are
## free to differ.

Bytes := [].{

	## Where `needle` first starts in `bytes` (std.mem.indexOf).
	find : List(U8), { needle : List(U8) } -> Try(U64, [NotFound])
	find = |bytes, { needle }| find_from(bytes, { needle, at: 0 })

	find_byte : List(U8), { byte : U8, at : U64 } -> Try(U64, [NotFound])
	find_byte = |bytes, { byte, at }| match bytes.get(at) {
		Ok(candidate) => if candidate == byte {
			Ok(at)
		} else {
			find_byte(bytes, { byte, at: at + 1 })
		}
		Err(_) => Err(NotFound)
	}

	## How many bytes from `at` on keep `keep`.
	count_while : List(U8), { keep : (U8 -> Bool), at : U64 } -> U64
	count_while = |bytes, { keep, at }| match bytes.get(at) {
		Ok(byte) if keep(byte) => count_while(bytes, { keep, at: at + 1 })
		_ => at
	}

	## How many `byte`s run from `at`.
	run_length : List(U8), { byte : U8, at : U64 } -> U64
	run_length = |bytes, { byte, at }| count_while(
		bytes,
		{ keep: |candidate| candidate == byte, at },
	) - at

	## How many bytes from the end keep `keep`.
	count_back : List(U8), (U8 -> Bool) -> U64
	count_back = |bytes, keep| count_back_from(bytes, { keep, kept: 0 })

	## `std.mem.trim(u8, s, set)`: the bytes in `set` off both ends.
	trim : List(U8), List(U8) -> List(U8)
	trim = |bytes, set| {
		in_set = |byte| set.contains(byte)
		front = bytes.drop_first(count_while(bytes, { keep: in_set, at: 0 }))
		front.drop_last(count_back(front, in_set))
	}

	## The four bytes Zig's `std.mem.trim(u8, s, " \t\r\n")` trims: not
	## `Ascii.is_whitespace`, which has VT and FF too.
	zig_spaces : List(U8)
	zig_spaces = [' ', '\t', '\r', '\n']

}

find_from : List(U8), { needle : List(U8), at : U64 } -> Try(U64, [NotFound])
find_from = |bytes, { needle, at }|
	if at + needle.len() > bytes.len() {
		Err(NotFound)
	} else if bytes.get(at) == needle.first() and bytes.sublist({
		start: at,
		len: needle.len(),
	}) == needle {
		Ok(at)
	} else {
		find_from(bytes, { needle, at: at + 1 })
	}

count_back_from : List(U8), { keep : (U8 -> Bool), kept : U64 } -> U64
count_back_from = |bytes, { keep, kept }|
	if kept >= bytes.len() {
		kept
	} else {
		match bytes.get(bytes.len() - 1 - kept) {
			Ok(byte) if keep(byte) => count_back_from(bytes, { keep, kept: kept + 1 })
			_ => kept
		}
	}
