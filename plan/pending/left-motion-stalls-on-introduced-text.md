# `left` stalls on projection-introduced text

## Symptom

Walking the cursor leftwards from Ctrl+End collapses after two or three carets on **every
syntax-backed document**, while the rightward walk from Ctrl+Home traverses the whole text:

| example | carets walking right | carets walking left |
|---|---|---|
| json | 348 | 3 |
| markdown | 395 | 11 |
| syntax | 84 | 3 |
| dragging | 68 | 3 |
| sql_insert_syntax | 51 | 3 |
| sql_update_syntax | 48 | 7 |
| formula | 32 | 4 |
| sql_syntax | 29 | 2 |
| focusing | 26 | 3 |
| json_insertion | 15 | 7 |

Pure-text examples (`text`, `plain_text`, `text_with_image`, `text_filtering`,
`text_highlighting`, `primitive_string`, `json_string`, `json_null`) are symmetric and unaffected.

Found by the bidirectional cursor walk added in
[text-navigation-right-to-left-walk.md](../done/text-navigation-right-to-left-walk.md); the ten
examples above are marked `@test_broken` in `test_text_nav_invariants_all` (see
`NAV_LEFT_WALK_STALLS` in [ExampleSweeps.jl](../../package/projectured/test/editor/ExampleSweeps.jl)).
Reproduce with:

```julia
julia> test_text_nav_invariants(syntax_example)          # the left walk fails its invariants
julia> test_text_nav_invariants(syntax_example; directions=(:left,))
```

## Diagnosis so far

Walking left from the end of the `syntax` example goes

1. `::SyntaxNode.close::TextString{1}::Position` — the Ctrl+End seed,
2. `::SyntaxNode.close::TextString{0}::Position`,
3. `SyntaxNodeProjectionReference(…, ::Position{82}::Position)`,

and there it **clamps in place**: `read_intent(…, KeyDown(:left))` returns the very selection it was
given. `right` from that same state advances normally, which is why the rightward walk never
noticed.

State 3 is a caret on *projection-introduced* text — the flat-offset position `SyntaxToText` emits
for the indentation, separators and collapse markers it adds itself, rather than a position inside a
domain node. `_text_char_motion`
([Text.jl:473](../../package/visual/main/text/Text.jl#L473)) clamps exactly when `_step_left`
returns `nothing`, and `_step_left` ([Text.jl:320](../../package/visual/main/text/Text.jl#L320))
returns `nothing` only at `(first span, char 0)`. So when that introduced-text selection is mapped
*forward* into the text layer, it lands at the start of the text rather than where it renders — the
caret draws in the right place, but the reader sees it at the beginning and refuses to move left.

Not yet established: which forward-map clause misplaces it. The suspects are the
`SyntaxNodeProjectionReference` cases around
[SyntaxToText.jl:190-215](../../package/visual/main/syntax/SyntaxToText.jl#L190-L215) and
[SyntaxToText.jl:253-313](../../package/visual/main/syntax/SyntaxToText.jl#L253-L313), which
re-anchor a flat offset through `_flat_to_text_elem_path`. Note `_flat_to_text_elem_path`
([SyntaxToText.jl:1216](../../package/visual/main/syntax/SyntaxToText.jl#L1216)) has an end-of-text
fallback that anchors to the *last non-empty span*; there is no matching guard on the way in, so a
flat offset that resolves to no span may be silently taking a wrong branch.

This is the same family as the fix recorded in the `introduced-token-caret-roundtrip` work, which
taught the forward map, the backward map and `_tree_navigate` about `ProjectionReference` carets.
That fix was validated rightwards only — the suite had no leftward walk until now.

## A second, narrower asymmetry

On `markdown`, `formula` and `sql_update_syntax` the *rightward* walk also ends somewhere other than
where Ctrl+End lands (`NAV_RIGHT_WALK_MISSES_END`). Likely the same forward-map misplacement seen
from the other side; worth re-checking once the left stall is fixed, since it may fall out with it.

## Steps

1. Instrument the forward map for the `syntax` example at the stalled state: print the text-level
   `(span, char)` that `SyntaxNodeProjectionReference(…Position{82})` maps to, and compare it with
   the `(span, char)` the rightward walk holds at the same visual caret. Confirm the placement is
   the start of the text.
2. Find the clause responsible and fix the placement so an introduced-text caret maps to the span it
   renders in.
3. Re-run the walks. The invariants to satisfy are already in the suite:
   `test_text_nav_invariants(example)` for each of the ten examples above.
4. As each example passes, remove it from `NAV_LEFT_WALK_STALLS` (an entry that starts passing shows
   up as an unexpectedly-passing `@test_broken`, so the suite will tell you).
5. Re-check `NAV_RIGHT_WALK_MISSES_END`; drop any entry that the fix also resolves.
