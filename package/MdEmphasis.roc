## **THE EMPHASIS ENGINE** (chat-markdown markdown_inline.zig's delimiter
## runs and `processEmphasis`): which `*` and `_` runs become `<em>` and
## `<strong>`. The hardest code in the package, and the most self-contained:
## the inline pass (MdInline) hands it each run as it meets one, then the
## line's runs all at once, and writes each run back out by `run_onto`. It
## reads no other markup, so a link or a code span is invisible to it.
##
## **HOW IT MATCHES, BY COMMONMARK'S DELIMITER STACK** (the spec's appendix,
## "process emphasis"):
##   - Each run is a `DelimiterRun`: its character, its length, and whether
##     it may open or close, from CommonMark's left- and right-flanking
##     (`flanking`: what stands just before and after it), with the extra
##     rule that an `_` run inside a word does neither.
##   - The runs are a doubly linked stack (`below`, `above`), walked from the
##     bottom. Each closer looks back down the stack for the nearest opener
##     of its character, and takes 2 from both (`<strong>`) when both have 2,
##     else 1 (`<em>`). Every run strictly between them leaves the stack;
##     a closer with delimiters left is looked at again.
##   - The rule of 3: a run that may both open and close matches only when
##     the two lengths' sum is no multiple of 3, unless both are.
##   - A closer that finds no opener sets a floor (`floor_key`) so no later
##     closer that would fail the same way looks below it again: what keeps
##     the walk linear.
##
## A matched run is never cut up: it records the emphasis it opens and
## closes (`opens`, `closes`) and keeps its unused delimiters as text, so the
## pass's pieces never move. **EVERY STEP IS CHARGED** to the budget, one
## unit per closer visited and per opener looked back at, the Zig's charges
## unit for unit. Pure.
import Ascii
import MdHtml
import MdText

MdEmphasis := [].{

	## A `*`/`_` run: its character, the delimiters it has left and had, whether
	## it may open and close, its neighbours on the stack (`below` is earlier),
	## and the emphasis it opens after it and closes before it, each `1`
	## (`<em>`) or `2` (`<strong>`), in the order matched.
	DelimiterRun : {
		char : U8,
		count : U64,
		orig : U64,
		can_open : Bool,
		can_close : Bool,
		below : Link,
		above : Link,
		opens : List(U64),
		closes : List(U64),
	}

	## The run `text[start..end]`, one character repeated, as the stack takes
	## it: whether it may open and close, and nothing matched yet.
	delimiter_run : List(U8), { start : U64, end : U64 } -> DelimiterRun
	delimiter_run = |text, { start, end }| {
		c = MdText.at(text, start)
		n = end - start
		flank = flanking(text, { start, end })
		# An `_` run inside a word neither opens nor closes.
		is_star = c == '*'
		can_open = flank.left and (is_star or !flank.right or flank.before_punct)
		can_close = flank.right and (is_star or !flank.left or flank.after_punct)
		{
			char: c,
			count: n,
			orig: n,
			can_open,
			can_close,
			below: Edge,
			above: Edge,
			opens: [],
			closes: [],
		}
	}

	## markdown_inline `processEmphasis`: the runs matched into emphasis by
	## CommonMark's delimiter stack, the rule of 3 included. One unit per
	## closer visited and per opener looked back at; blown on a closer is
	## hostile, and the caller checks once more after.
	emphasis : { runs : List(DelimiterRun), budget : MdText.Budget } -> Try(
		{ runs : List(DelimiterRun), budget : MdText.Budget },
		[Hostile],
	)
	emphasis = |{ runs, budget }| {
		n = List.len(runs)
		var $runs = List.map_with_index(
			runs,
			|run, k| {
				..run,
				below: if k == 0 Edge else At(k - 1),
				above: if k + 1 == n Edge else At(k + 1),
			},
		)
		var $budget = budget
		# The lowest opener a closer may look back to, by its floor key: an
		# edge is the stack's bottom.
		var $bottoms = List.repeat(Edge, floor_keys)
		var $closer = if n == 0 Edge else At(0)
		while $closer != Edge {
			ci = index_of($closer)
			$budget = MdText.charge($budget, 1)
			if MdText.is_blown($budget) {
				return Err(Hostile)
			} else {
				{}
			}
			closer = MdEmphasis.run_at($runs, ci)
			if !closer.can_close {
				$closer = closer.above
			} else {
				slot = floor_key(closer)
				bottom = List.get($bottoms, slot) ?? Edge
				var $opener = closer.below
				var $found = Bool.False
				while $opener != Edge {
					$budget = MdText.charge($budget, 1)
					if $opener == bottom {
						break
					} else {
						{}
					}
					opener = MdEmphasis.run_at($runs, index_of($opener))
					# The rule of 3: a run that may both open and close matches
					# another only when their lengths' sum is no multiple of 3,
					# unless both are.
					is_both = closer.can_open or opener.can_close
					odd = is_both and closer.orig % 3 != 0 and (opener.orig + closer.orig) % 3 == 0
					if opener.can_open and opener.char == closer.char and !odd {
						$found = Bool.True
						break
					} else {
						{}
					}
					$opener = opener.below
				}
				if $found {
					oi = index_of($opener)
					opener = MdEmphasis.run_at($runs, oi)
					use = if opener.count >= 2 and closer.count >= 2 2 else 1
					# Every run strictly between the two leaves the stack.
					$runs = set_run(
						$runs,
						{
							at: oi,
							delimiters: {
								..opener,
								count: opener.count - use,
								above: At(ci),
								opens: List.append(opener.opens, use),
							},
						},
					)
					$runs = set_run(
						$runs,
						{
							at: ci,
							delimiters: {
								..closer,
								count: closer.count - use,
								below: At(oi),
								closes: List.append(closer.closes, use),
							},
						},
					)
					if opener.count == use {
						$runs = unlinked($runs, oi)
					} else {
						{}
					}
					if closer.count == use {
						above = MdEmphasis.run_at($runs, ci).above
						$runs = unlinked($runs, ci)
						$closer = above
					} else {
						{}
					}
					# A closer with delimiters left is looked at again.
				} else {
					$closer = closer.above
					$bottoms = List.set(
						$bottoms,
						slot,
						closer.below,
					) ?? crash "MdEmphasis: a bottom's slot past the floor keys"
					if !closer.can_open {
						$runs = unlinked($runs, ci)
					} else {
						{}
					}
				}
			}
		}
		Ok({ runs: $runs, budget: $budget })
	}

	## Run `k` of the line's runs.
	run_at : List(DelimiterRun), U64 -> DelimiterRun
	run_at = |runs, k| match List.get(runs, k) {
		Ok(run) => run
		Err(OutOfBounds) => crash "MdEmphasis: a run's index past the runs"
	}

	## A matched run written onto `out`: the emphasis it closes, its
	## delimiters left, and the emphasis it opens, innermost nearest. (The Zig
	## splices marker nodes into its linked list beside each run; a marker is
	## only ever spliced beside a run, so a run's own lists, in this order,
	## are the same sequence.)
	run_onto : List(U8), DelimiterRun -> List(U8)
	run_onto = |out, run| {
		var $o = out
		for use in run.closes {
			$o = List.concat($o, if use == 2 MdHtml.strong_close else MdHtml.em_close)
		}
		$o = List.concat($o, List.repeat(run.char, run.count))
		var $n = List.len(run.opens)
		while $n > 0 {
			$n = $n - 1
			$o = List.concat(
				$o,
				if (List.get(run.opens, $n) ?? 0) == 2 MdHtml.strong_open else MdHtml.em_open,
			)
		}
		$o
	}
}

## A run's neighbour on the delimiter stack: another run, or the edge.
Link : [Edge, At(U64)]

index_of : Link -> U64
index_of = |link| match link {
	At(k) => k
	Edge => crash "MdEmphasis: the stack's edge read as a run"
}

set_run : List(MdEmphasis.DelimiterRun), { at : U64, delimiters : MdEmphasis.DelimiterRun } -> List(MdEmphasis.DelimiterRun)
set_run = |runs, { at, delimiters }| List.set(
	runs,
	at,
	delimiters,
) ?? crash "MdEmphasis: a run set past the runs"

## **THE FLOOR'S KEY, COMMONMARK'S** (commonmark.js's `openers_bottom`,
## markdown-it's): a closer's character, whether it may also open, and its
## run's length as written, mod 3. A closer that failed sets the floor only
## for closers that would fail the same way: the rule of 3 reads both of
## these, so a key without them lets one closer's failure stop another that
## would have matched (`*a**b** c**`'s last `**`). The Zig keys on what is
## left of the run and its character alone.
floor_key : MdEmphasis.DelimiterRun -> U64
floor_key = |closer| {
	opens = if closer.can_open 3 else 0
	(opens + closer.orig % 3) * 2 + (if closer.char == '*' 0 else 1)
}

## The floor keys: two characters, by can_open, by length mod 3.
floor_keys : U64
floor_keys = 12

## markdown_inline `unlinkDelim`: run `k` off the stack; its place among the
## pieces, and its delimiters left, stay.
unlinked : List(MdEmphasis.DelimiterRun), U64 -> List(MdEmphasis.DelimiterRun)
unlinked = |runs, k| {
	run = MdEmphasis.run_at(runs, k)
	with_below = match run.below {
		At(b) => set_run(runs, { at: b, delimiters: { ..MdEmphasis.run_at(runs, b), above: run.above } })
		Edge => runs
	}
	match run.above {
		At(a) => set_run(with_below, { at: a, delimiters: { ..MdEmphasis.run_at(with_below, a), below: run.below } })
		Edge => with_below
	}
}

## markdown_inline `flanking`: CommonMark's left- and right-flanking for the
## run `text[start..end]`; the line's ends count as space.
flanking : List(U8),
{
	start : U64,
	end : U64,
} -> {
	left : Bool,
	right : Bool,
	before_punct : Bool,
	after_punct : Bool,
}
flanking = |text, { start, end }| {
	before = if start == 0 ' ' else MdText.at(text, start - 1)
	after = if end >= List.len(text) ' ' else MdText.at(text, end)
	before_space = MdText.is_space(before)
	after_space = MdText.is_space(after)
	before_punct = Ascii.is_punctuation(before)
	after_punct = Ascii.is_punctuation(after)
	{
		left: !after_space and (!after_punct or before_space or before_punct),
		right: !before_space and (!before_punct or after_space or after_punct),
		before_punct,
		after_punct,
	}
}
