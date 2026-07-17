# JSON leftward-navigation loop (widened-indent caret round-trip)

## Symptom

In `json_example`, Ctrl+End then repeated Left navigates most of the document but
eventually **oscillates** between two carets and never reaches the start. The
bidirectional cursor walk (`test_text_nav_invariants`) reports this as
`:cycle_left`, and the leftward walk visits far fewer carets than the rightward
one (`:same_length`, `:left_reaches_start`). Marked `@test_broken` for `json` and
`json_sorted` (and `mixed`, `yaml`) in `ExampleSweeps.jl`.

## Root cause (established, this branch)

Not the width-0 indent-slot stall of
[left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md)
— that was fixed when the Text cursor became a flat `±1` offset. The residual is a
**forward/backward map inconsistency for carets inside a *widened* indent span.**

`SyntaxToText` re-indents on splice: a child's trailing indent span (empty, `""`,
in the child's own output) is **widened** to `"  "` when spliced into an indenting
ancestor (`_splice_child!` → `_widen_indent_span`). So at the parent level the
span has width 2 and offers caret positions the child's zero-width version cannot.

`map_reference_forward` widens (it re-anchors child cursors over the parent's
*widened* spans). `map_reference_backward` did the opposite: `_backward_zone`,
finding the caret's span inside a child's element range, **delegated** the
`(span, char)` into the child's mapper, which re-flattened `char` over the child's
*un-widened* (zero-width) spans — collapsing the caret onto the following close
delimiter. Concretely, on `json_example`:

```
elem[176] "  "  flat[340,342)   trailing indent (widened)
elem[177] "}"   flat[342,343)   close delimiter of children[7].children[2]

backward(340) → close{0}  (forward → 342)   ✗  off by +2 (the widening)
backward(341) → close{1}  (forward → 343)   ✗
backward(342) → close{0}  (forward → 342)   ✓
```

So `forward(backward(f)) = f + 2` for every caret inside a widened indent — **32
of 384 flats** on `json_example`, one pair per indented line. Stepping Left off
`close{0}` (flat 342) went to flat 341, whose backward was `close{1}` (flat 343),
and Left off that returned to `close{0}`: the loop.

Diagnosed with a per-step flat-offset dump of the leftward walk and a full
`forward(backward(f))` round-trip audit over the `SyntaxToText` output.

## Fix

`package/visual/main/syntax/SyntaxToText.jl`, `_backward_zone`: an **indent span is
pure whitespace chrome, rendered at this level's widened width**. A caret inside
one has no counterpart in the child's narrower version, so it must map to a
projection-introduced position *here* rather than delegate into the child. Detect
it with `iomap.indent_indices[]` (exactly the whitespace indent spans — this
node's own plus each spliced child's) and let a cursor there fall through to the
existing introduced-position branch. ∅ (whole-element) queries still delegate.

Backward now round-trips for every flat (`forward(backward(f)) == f`), so both
walks are clean chains that meet in the middle.

## Result

- Round-trip audit on `json_example`: **0 / 384** broken flats (was 32).
- `test_text_nav_invariants` now passes **unannotated** (11/11) for `json`,
  `json_sorted`, `mixed`, `yaml` — all four had the same widened-indent cause.
- No control regressed (`syntax`, `markdown`, `dragging`, `sql_syntax`,
  `sql_insert_syntax`, `sql_update_syntax`, `focusing`, `json_insertion`).
- Still broken, unrelated causes (kept in `NAV_LEFT_WALK_STALLS`): `formula`
  (walk leaves the subtree), `text` / `text_with_image` (plain-Text asymmetry, no
  projection), `markdown_rendered` (rendered inline chrome).

## Test-table changes (`package/projectured/test/editor/ExampleSweeps.jl`)

- `NAV_LEFT_WALK_STALLS`: drop `json`, `json_sorted`, `mixed`, `yaml`.
- `NAV_LEFT_WALK_CYCLES`: **removed** (no example cycles now); `nav_broken` drops
  its `:cycle_left` branch. The `:cycle_left` capability stays in
  `test_text_nav_invariants`.

## Regression sweep (worktree vs clean main)

| suite | main | worktree | note |
|---|---|---|---|
| `TextNavInvariants` | 220 pass / 25 broken | 232 / 13 | +12 pass, −12 broken (json, json_sorted, mixed, yaml) |
| `PositionNavigationComplete` json | 495 / 22 / 1 broken | 523 / 22 / 1 | +28 reachable, **0 new fails** |
| `PositionNavigationComplete` text | 451 / 449 | 451 / 449 | identical — pre-existing, not this change |
| `TreeNavigationComplete` | 144 / 1 | 144 / 1 | unchanged |
| `MouseClicks` | 27 / 3 | 27 / 3 | no click regression |
| `syntax_to_text` | green | green | unchanged |

Bonus: `sql_nested_syntax` (skipped in the sweep for a *rightward* introduced-caret
cycle) — its leftward walk no longer cycles (236 states); the rightward cycle is a
different introduced caret and remains, so it stays skipped.

json's `.entries[8].value` insertion slot is **still** unreached on both trees
(1 broken, unchanged), so its `unreached_broken` marker stays.

## Steps

- [x] Reproduce the oscillation; dump per-step flat offsets.
- [x] Round-trip audit → isolate the 32 widened-indent flats.
- [x] Trace `_backward_zone` delegation → widened-vs-un-widened span mismatch.
- [x] Fix `_backward_zone`; verify 0/384 and json/json_sorted green.
- [x] Confirm the fix generalises (mixed, yaml) and regresses no control.
- [x] Update the broken tables + comments.
- [x] Regression sweep vs clean main — no regressions (table above).
- [x] json's `.entries[8].value` slot still unreached → keep its `unreached_broken`.
