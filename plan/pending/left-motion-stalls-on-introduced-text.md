# `left` stalls on projection-introduced text

## Symptom

Walking the cursor leftwards from Ctrl+End collapses after two or three carets on **every**
syntax-backed document, while the rightward walk from Ctrl+Home traverses the whole text:

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

Pure-text examples are symmetric and unaffected. Found by the bidirectional cursor walk
([text-navigation-right-to-left-walk.md](../done/text-navigation-right-to-left-walk.md)); the ten
examples are marked `@test_broken` via `NAV_LEFT_WALK_STALLS` in
[ExampleSweeps.jl](../../package/projectured/test/editor/ExampleSweeps.jl). Reproduce with
`test_text_nav_invariants(syntax_example)`.

## Root cause (established)

**A zero-length span swallows the step.**

`SyntaxToText` deliberately emits an *empty* `TextString` for the trailing indent before a node's
close delimiter — [SyntaxToText.jl:479-486](../../package/visual/main/syntax/SyntaxToText.jl#L479-L486):
"an empty span is still emitted so there is always a slot to widen and element counts never depend
on depth". The `syntax` example's flattened text has 29 such empty spans; span 85 of 86 is one,
sitting between the last child and the closing `)`.

`_step_left` ([Text.jl:320](../../package/visual/main/text/Text.jl#L320)) at `(86, 0)` takes the
`char_idx == 0` branch and returns `(85, max(0, len₈₅ - 1))` = **`(85, 0)`**. Because span 85 is
empty, that is the *same visual caret* it started from: its flat offset is identical (82), so
`SyntaxToText`'s backward map produces the very domain path the cursor already held. The selection
does not change, the walk sees a fixed point, and leftward motion dies. Every syntax-backed document
has this empty indent span before its closing delimiter, which is exactly why they all stall two or
three carets in from the end and pure text never does.

`_step_right` has the same latent flaw (`next[2] > 0 ? 1 : 0` lands on `(next, 0)` when the next span
is empty); it is simply not reached from the right, because the forward map never resolves a domain
position *into* an empty span.

## The obvious fix is wrong — do not try it

Making `_step_left` / `_step_right` skip empty spans **fixes 8 of the 10 examples** (syntax 3→84,
sql_syntax 2→29, markdown 11→394, all symmetric) and is still **wrong**. It was implemented,
measured, and reverted. Here is why, so nobody rediscovers it the hard way.

**Not every empty span is decoration.** An undelimited `SyntaxLeaf` has an empty `.open` and an empty
`.close`, and those are legitimate, distinct, addressable carets. `json_null` renders `null` as
exactly that:

```
right walk:  .open{0} → .value{1} → .value{2} → .value{3} → .value{4}
Ctrl+End  →  .close{0}      ← an empty span, and the correct end-of-text caret
```

With empty spans skipped, the rightward walk can no longer reach `.close{0}` and stops at
`.value{4}`: a real caret is silently deleted, and `json_null` — previously green — starts failing
`right_reaches_end`.

Ctrl+Home/Ctrl+End cannot be "fixed" to match, either. Anchoring the jump on the outermost
*non-empty* span moves the caret onto a number/bool leaf's rendered text, and
`PrimitiveNumberToSyntaxLeaf` maps that back to `.value::Number{k}` — a caret *inside a number* —
which the strict reference checker rejects as under-typed. That regresses `TableNavigation`
(math_table: Enter-into-cell throws) from 63/0/1 to 60/2/2.

So the discriminator is **not** emptiness:

| span | empty? | has its own caret? |
|---|---|---|
| `SyntaxToText`'s width-0 trailing indent | yes | **no** — its flat offset collides with the next span's |
| an undelimited leaf's `.open` / `.close` | yes | **yes** — a distinct domain path |
| any content span | no | yes |

The Text layer cannot tell these apart: `TextString` carries no marker saying "I am projection
chrome", and both cases are a zero-length `TextString`.

## What a real fix needs

The degeneracy is created in `SyntaxToText._backward_zone`
([SyntaxToText.jl:333](../../package/visual/main/syntax/SyntaxToText.jl#L333)): for its *own* chrome
spans it encodes the caret as a flat offset, and an empty chrome span's flat offset equals its
neighbour's. A child's empty `.open` does not collide, because it is routed through the child zone to
the child's own mapper and keeps a distinct path. So the projection knows which spans are caretless;
the Text layer does not. Options, roughly in order of appeal:

1. **Mark chrome spans in the document.** Give `TextString` a flag (or a distinct span type) that
   `SyntaxToText` sets on the decorative spans it creates. The steppers then skip a span only when it
   is *both* empty *and* chrome — exactly the rule that holds. Costs a field on a `@document` struct
   and touches the printer, but it is the honest model: the text layer is being asked a question it
   currently has no data to answer.
2. **Emit the empty indent as a `TextSpacing(0)` rather than a `TextString("")`.** `_text_span_infos`
   only collects `TextString` spans, so a spacing span is invisible to the cursor machinery while
   still occupying the element slot the widening code needs. Requires `_flat_to_text_elem_path` and
   `_widen_indent_span` to handle a non-`TextString` slot.
3. Reconcile the forward/backward maps so an empty chrome span has no representable caret at all.

Whatever the route, the fix belongs in `SyntaxToText` + the span model, **not** in the generic
steppers.

## Also found, still open

Two failures are *not* the empty-span stall — they survive it and need separate work. Both are
forward/backward map inconsistencies for introduced positions inside **child** projections:

- **json** oscillates. Walking left, a nested node's `close{0}` and that node's own introduced offset
  `/SyntaxNodeToText({65})` map to adjacent-but-inconsistent carets: `backward(T-1)` yields `{65}`
  while `forward({65})` yields `T+1`, so `left` bounces between the two forever (the walk reports a
  cycle).
- **formula** walks left out of one formula's syntax children into a *different* subtree
  (`.formulas[3:4].code.right/JuliaIntegerToSyntaxLeaf(.value{0})`) and then declines to move.

## Steps

1. Pick a route from "What a real fix needs" (1 is recommended).
2. Implement it in `SyntaxToText` + the span model. The steppers should need no change.
3. Verify with `test_text_nav_invariants(syntax_example)`, then `test_text_nav_invariants_all()`.
   Expect the 8 stalling examples to go symmetric.
4. **Guard against the trap above**: `test_text_nav_invariants(json_null_example)` must stay green
   (its `.close{0}` caret must remain reachable), and `test_table_navigation()` must stay at its
   63 pass / 0 fail / 1 error / 1 broken baseline.
5. Shrink `NAV_LEFT_WALK_STALLS` to `("json", "formula")` and `NAV_RIGHT_WALK_MISSES_END` to
   `("formula",)`. A new `:cycle_left` broken marker is then needed for json's oscillation — and for
   yaml, whose leftward walk only gets far enough to cycle once the stall is gone.
6. Then tackle the two residual child-projection inconsistencies above.
