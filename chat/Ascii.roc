## ASCII BYTE CHECKS, AS ZIG'S std.ascii HAS THEM: seven questions about one
## byte, and its two case maps. Pure.
##
## **ONE BYTE AT A TIME, SAFE ON UTF-8 BY CONSTRUCTION.** Every byte of a
## multi-byte UTF-8 character is 128 or above, and no byte from 128 to 255 is
## ASCII: every check here answers `Bool.False` for it and both case maps
## return it unchanged. So these run over `Str.to_utf8` bytes as they are,
## for parsing ASCII-defined syntax inside UTF-8 text (a header, a URL, a
## Markdown marker, a number) without ever splitting a character. Whether a
## character is a letter or a space in Unicode's sense is out of scope.
##
## Plain functions on `U8`, called on the bytes a parser already holds, with
## no wrapper type: Hasnep/roc-ascii instead offers an ASCII-only text type
## (`Char :: U8`, `Ascii :: List(Char)`), a different and larger thing.
##
## The sets are C's `<ctype.h>` (in the C locale), Zig's `std.ascii` and
## Rust's `u8::is_ascii_*`, which agree on all of them but whitespace (see
## `is_whitespace`).
Ascii := [].{

	## `0`-`9` (48-57). Zig `isDigit`, Rust `is_ascii_digit`, C `isdigit`.
	## `Bool.False` for every byte from 128 to 255.
	is_digit : U8 -> Bool
	is_digit = |c| c >= '0' and c <= '9'

	## `0`-`9`, `A`-`F` and `a`-`f` (48-57, 65-70, 97-102). Zig `isHex`,
	## Rust `is_ascii_hexdigit`, C `isxdigit`. `Bool.False` for every byte
	## from 128 to 255.
	is_hex_digit : U8 -> Bool
	is_hex_digit = |c| is_digit(c) or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')

	## `A`-`Z` and `a`-`z` (65-90, 97-122). Zig `isAlphabetic`, Rust
	## `is_ascii_alphabetic`, C `isalpha`. `Bool.False` for every byte from
	## 128 to 255, so `é` (bytes 195 169) is no letter here.
	is_alphabetic : U8 -> Bool
	is_alphabetic = |c| (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')

	## `0`-`9`, `A`-`Z` and `a`-`z`: `is_digit` or `is_alphabetic`. Zig
	## `isAlphanumeric`, Rust `is_ascii_alphanumeric`, C `isalnum`.
	## `Bool.False` for every byte from 128 to 255.
	is_alphanumeric : U8 -> Bool
	is_alphanumeric = |c| is_digit(c) or is_alphabetic(c)

	## The six bytes of C's `isspace`, which Zig's `isWhitespace` and Go's
	## `strings.Fields` share: space (32) and 9-13, which are `\t`, `\n`,
	## vertical tab (VT, 11), form feed (FF, 12) and `\r`. Rust's
	## `is_ascii_whitespace` and WHATWG's "ASCII whitespace" (HTML, URLs)
	## leave VT out, and JSON allows only space, `\t`, `\n` and `\r`: a parser
	## for a format with its own set (JSON, HTTP) uses that format's set, not
	## this. `Bool.False` for every byte from 128 to 255, so a no-break space
	## (bytes 194 160) is not whitespace here.
	is_whitespace : U8 -> Bool
	is_whitespace = |c| c == ' ' or (c >= '\t' and c <= '\r')

	## The 32 printable bytes that are neither letters, digits nor space:
	## ``!"#$%&'()*+,-./`` (33-47), `:;<=>?@` (58-64), ``[\]^_` `` (91-96)
	## and `{|}~` (123-126). Zig `isPunctuation`, Rust
	## `is_ascii_punctuation`, C `ispunct`, Python `string.punctuation`.
	## `Bool.False` for every byte from 128 to 255.
	is_punctuation : U8 -> Bool
	is_punctuation = |c| c > ' ' and c < del and !is_alphanumeric(c)

	## 0-31 and DEL (127): every ASCII byte that is not printable. Zig
	## `isControl`, Rust `is_ascii_control`, C `iscntrl`. `Bool.False` for
	## every byte from 128 to 255.
	is_control : U8 -> Bool
	is_control = |c| c < ' ' or c == del

	## `A`-`Z` to `a`-`z`; every other byte, 128 to 255 included, unchanged.
	## Zig `toLower`, Rust `to_ascii_lowercase`, C `tolower`, and the per-byte
	## rule of `Str.with_ascii_lowercased`. Branchless, as Zig's is: an
	## uppercase letter differs from its lowercase only in bit 5 (0x20), so
	## that bit is ORed in when the byte is `A`-`Z` (`case_bit`).
	to_lower : U8 -> U8
	to_lower = |c| c.bitwise_or(case_bit(c.minus_wrap('A')))

	## `a`-`z` to `A`-`Z`; every other byte, 128 to 255 included, unchanged.
	## Zig `toUpper`, Rust `to_ascii_uppercase`, C `toupper`, and the per-byte
	## rule of `Str.with_ascii_uppercased`. Branchless, as `to_lower`: bit 5
	## is XORed out when the byte is `a`-`z`.
	to_upper : U8 -> U8
	to_upper = |c| c.bitwise_xor(case_bit(c.minus_wrap('a')))
}

## DEL, the one control byte above the printable ones. Roc's character
## literals have no escape for it.
del : U8
del = 127

## 0x20 when `offset` (a byte minus `A`, or minus `a`, wrapping) is below 26,
## so the byte is a letter of that case; 0 otherwise. Zig writes this mask as
## `@intFromBool(isUpper(c)) << 5`, but a Roc `Bool` is a tag with no number
## in it, so the mask is arithmetic instead, with no comparison and no
## branch. An offset below 26 has bit 7 clear, and so does the offset plus
## 102 (128 - 26); an offset from 26 to 127 sets bit 7 of the sum, and one
## from 128 up sets its own. Bit 7 clear in both, moved down to bit 5, is the
## mask.
case_bit : U8 -> U8
case_bit = |offset|
	offset
		.bitwise_or(offset.plus_wrap(128 - 26))
		.bitwise_not()
		.bitwise_and(0x80)
		.shr_wrap(2)

# ── tests ──
# Each set is written out below as its members, in byte order, not as the
# ranges the code tests, and every check is held to it over all 256 bytes.

all_bytes : List(U8)
all_bytes = Iter.fold(
	U8.to(0, 255),
	[],
	|acc, b| acc.append(b),
)

ascii : List(U8)
ascii = List.take_first(all_bytes, 128)

beyond_ascii : List(U8)
beyond_ascii = List.drop_first(all_bytes, 128)

digits : List(U8)
digits = Str.to_utf8("0123456789")

uppers : List(U8)
uppers = Str.to_utf8("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

lowers : List(U8)
lowers = Str.to_utf8("abcdefghijklmnopqrstuvwxyz")

punctuation : List(U8)
punctuation = Str.to_utf8("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

# VT and FF have no escape in a Roc literal.
whitespace : List(U8)
whitespace = [
	'\t',
	'\n',
	11,
	12,
	'\r',
	' ',
]

# The 95 printable bytes: everything ASCII but the control bytes.
printable : List(U8)
printable = List.join([
	[' '],
	punctuation,
	digits,
	letters,
])

letters : List(U8)
letters = List.concat(uppers, lowers)

# The 33 control bytes, stated as ASCII less the printables.
controls : List(U8)
controls = List.keep_if(ascii, |b| !List.contains(printable, b))

non_letters : List(U8)
non_letters = List.keep_if(all_bytes, |b| !List.contains(letters, b))

expect List.len(all_bytes) == 256
expect List.len(punctuation) == 32
expect List.len(printable) == 95
expect List.len(controls) == 33

# Each check over all 256 bytes is exactly its set.
expect List.keep_if(all_bytes, Ascii.is_digit) == digits
expect List.keep_if(all_bytes, Ascii.is_hex_digit) == Str.to_utf8("0123456789ABCDEFabcdef")
expect List.keep_if(all_bytes, Ascii.is_alphabetic) == letters
expect List.keep_if(all_bytes, Ascii.is_alphanumeric) == List.concat(digits, letters)
expect List.keep_if(all_bytes, Ascii.is_whitespace) == whitespace
expect List.keep_if(all_bytes, Ascii.is_punctuation) == punctuation
expect List.keep_if(all_bytes, Ascii.is_control) == controls

# 128-255 are never ASCII: every check is false, and the case maps keep them.
expect List.all(
	[
		Ascii.is_digit,
		Ascii.is_hex_digit,
		Ascii.is_alphabetic,
		Ascii.is_alphanumeric,
		Ascii.is_whitespace,
		Ascii.is_punctuation,
		Ascii.is_control,
	],
	|check| !List.any(beyond_ascii, check),
)
expect List.map(beyond_ascii, Ascii.to_lower) == beyond_ascii
expect List.map(beyond_ascii, Ascii.to_upper) == beyond_ascii

# The bytes on each side of every range: of each probe, the members.
expect List.keep_if(Str.to_utf8("/09:"), Ascii.is_digit) == Str.to_utf8("09")
expect List.keep_if(Str.to_utf8("/09:@AFG`afg"), Ascii.is_hex_digit) == Str.to_utf8("09AFaf")
expect List.keep_if(Str.to_utf8("@AZ[`az{"), Ascii.is_alphabetic) == Str.to_utf8("AZaz")
expect List.keep_if(Str.to_utf8("/09:@AZ[`az{"), Ascii.is_alphanumeric) == Str.to_utf8("09AZaz")
expect List.keep_if(
	[
		8,
		'\t',
		'\r',
		14,
		31,
		' ',
		'!',
	],
	Ascii.is_whitespace,
) == Str.to_utf8("\t\r ")
expect List.keep_if(Str.to_utf8(" !/09:@AZ[`az{~"), Ascii.is_punctuation) == Str.to_utf8("!/:@[`{~")
expect List.keep_if(
	[
		0,
		31,
		' ',
		'~',
		127,
		128,
	],
	Ascii.is_control,
) == [
	0,
	31,
	127,
]
expect List.map(Str.to_utf8("@AZ[`az{"), Ascii.to_lower) == Str.to_utf8("@az[`az{")
expect List.map(Str.to_utf8("@AZ[`az{"), Ascii.to_upper) == Str.to_utf8("@AZ[`AZ{")

# The case maps: each letter to its pair, each letter already in the case
# kept, every other byte (204 of them) unchanged.
expect List.map(uppers, Ascii.to_lower) == lowers
expect List.map(lowers, Ascii.to_lower) == lowers
expect List.map(lowers, Ascii.to_upper) == uppers
expect List.map(uppers, Ascii.to_upper) == uppers
expect List.len(non_letters) == 204
expect List.map(non_letters, Ascii.to_lower) == non_letters
expect List.map(non_letters, Ascii.to_upper) == non_letters

# Every letter round-trips through the other case.
expect List.map(lowers, |b| Ascii.to_lower(Ascii.to_upper(b))) == lowers
expect List.map(uppers, |b| Ascii.to_upper(Ascii.to_lower(b))) == uppers
