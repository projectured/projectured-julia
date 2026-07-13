# Text navigation: walk the cursor right-to-left end-to-end

## Problem

`test_text_nav_invariants` ([package/visual/test/editor/ClickRoundtripTest.jl](../../package/visual/test/editor/ClickRoundtripTest.jl))
is the only end-to-end *linear* cursor walk in the suite. It does exactly one thing:

1. seed with `Ctrl+Home`,
2. fire `KeyDown(:right)` repeatedly, re-printing between steps,
3. assert the walk terminates, takes at least one step, and never revisits the previous state.

So `left` is never exercised end-to-end. The BFS driver (`test_position_navigation`,
[NavigationTest.jl](../../package/kernel/test/editor/NavigationTest.jl)) *does* fire `left`, but as
one of ten keys in a reachability search — it asserts "no reader threw" and "the enumerated
positions are reachable", never "walking left from the end retraces the walk right from the start".
A `left` reader that skips a caret, stalls one position early, or lands on a different (but
still valid) path than `right` produced would pass everything we have today.

The gap matters because `left` and `right` are implemented by separate motion code paths
(`_text_word_motion` / the character-motion readers in
[package/visual/main/text/Text.jl](../../package/visual/main/text/Text.jl)) and because
projection-introduced tokens (delimiters, indentation, collapsed ellipses) are the places where
the two directions are most likely to disagree — exactly the area the
`introduced-token-caret-roundtrip` fix touched.

## Goal

Walk the cursor end-to-end in **both** directions and assert the two walks describe the same caret
chain:

- **rightward** (existing): `Ctrl+Home`, then `right` until fixed point.
- **leftward** (new): `Ctrl+End`, then `left` until fixed point.
- **cross-direction** (new, the real payoff): the two walks must agree — same states, mirrored
  endpoints, ideally reverse order.

`Ctrl+End` is already a supported seed gesture
([Text.jl:304](../../package/visual/main/text/Text.jl#L304)) and is already in `POSITION_NAV_KEYS`,
so no reader work is expected — this is a test-side change. If the leftward walk turns up reader
bugs, those are the point of the exercise; they get recorded here, not silently skipped.

Out of scope: `up`/`down`/`home`/`end`/word-motion coverage (the BFS already fires those), and the
click round-trip half of the same file.

## Invariants to assert

Per direction (both walks, symmetric):

- **P1** The seed gesture yields a `ReplaceSelectionOperation`.
- **P2** Every step yields a state not yet visited *in this walk* — strengthened from today's
  `new != prev` (which catches an immediate fixed point but not a 2-cycle) to `new ∉ visited`.
- **P3** The walk terminates (reader returns `nothing`, or the state is a fixed point) inside
  `max_steps`.
- **P4** At least one step is taken.

Across directions:

- **X1** The rightward walk's terminal state equals the `Ctrl+End` seed state. (Walking right to
  exhaustion lands where `Ctrl+End` jumps.)
- **X2** The leftward walk's terminal state equals the `Ctrl+Home` seed state.
- **X3** The two walks visit the same **set** of states.
- **X4** (strongest) `left_walk == reverse(right_walk)` as ordered sequences.

X3 and X4 are what actually catch a direction-asymmetric reader. X4 may legitimately fail where a
caret position is representable by two paths that render identically (the end-of-line /
start-of-next-line ambiguity the click round-trip already tolerates), so it is measured before it is
asserted — see Step 3.

## Open question to resolve by measurement (Step 2)

The existing walk keys `visited` on `string(op.path)` — the **raw** path, type checkpoints included.
The BFS driver instead dedups on `string(strip_reference_types(path))`. For a cross-direction
comparison this matters: if the `left` reader folds a node type where `right` does not, X3/X4 would
fail on a difference that is not a navigation bug.

Decision: keep the **raw** string for the within-walk P2 distinctness assertion (stripping could
merge two genuinely distinct states and break `length(visited) == steps + 1`), and use the
**stripped** string for the cross-direction X1–X4 comparisons. If measurement shows the raw strings
already agree in both directions, drop the stripping from the comparison and note it here.

## Steps

Work in a dedicated worktree, one commit per step.

### Step 1 — factor out a direction-parameterized walk — **done**

Replace the inline loop in `test_text_nav_invariants` with a helper that both directions share:

```julia
# Returns (path_strs::Vector{String}, terminated::Bool, error::Union{Nothing,String})
_walk_cursor(document, projection; seed::KeyDown, step::KeyDown, max_steps=10_000)
```

It seeds, then steps, recording the ordered list of visited path strings (seed first). It returns
the *sequence*, not a set — X4 needs the order. `test_text_nav_invariants` calls it once with
`(seed=Ctrl+Home, step=right)` and asserts P1–P4 exactly as today. Behavior-neutral refactor: the
sweep result must be unchanged.

**Verify:** `test_text_nav_invariants(json_example)` and one non-JSON example (`text`, `syntax`)
give the same pass counts as before the refactor.

### Step 2 — add the leftward walk, and measure — **done** (see Findings)

Call `_walk_cursor` a second time with `(seed=Ctrl+End, step=left)` and assert P1–P4 on it too.
Add a `directions=(:right, :left)` keyword so a single direction can be run in isolation while
debugging.

Then **measure before asserting anything cross-direction**: run
`test_text_nav_invariants_all()` and, for every example the sweep does not already skip, record in
this plan:

| example | right steps | left steps | X1 | X2 | X3 | X4 |
|---|---|---|---|---|---|---|

Examples where the leftward walk fails wholesale (e.g. `Ctrl+End` yields no selection — the known
`Ctrl+Home` seed failures in the green baseline suggest a mirror class exists) go into the sweep's
existing skip-with-reason list, in the same style as the current comment block, naming the reason.
Do not paper over a partial failure — a left walk that stops short of the start is a finding, and
belongs in the table above and in the summary at the end of this plan.

**Verify:** `test_text_nav_invariants(json_example)`, then the full
`test_text_nav_invariants_all()` sweep.

### Step 3 — cross-direction invariants — **done** (asserted as same_length / right_reaches_end / left_reaches_start; caret-sequence equality dropped, see Findings)

Add X1, X2, X3 as `@test`s. Add X4 too, but gate it on what Step 2's table showed: where the order
reversal genuinely fails because of the line-boundary path ambiguity, mark it `@test_broken` with a
`# @broken:` comment naming the example and the ambiguity (per the repo's
"Marking known-failing tests" convention), rather than deleting the assertion.

If X3 fails for an example, that is a real direction-asymmetry bug in a reader — stop and
investigate it before marking anything broken. Record the diagnosis here.

**Verify:** the sweep again; `Fail`/`Error` must stay at zero, and any change in the `Broken` count
must be explained by a `# @broken:` marker added in this step.

### Step 4 — docs — **done**

- Update the `ClickRoundtripTest.jl` header comment: `test_text_nav_invariants` now walks both
  directions and cross-checks them. (Describe what it *is*, not that it changed.)
- Add a row for `test_text_nav_invariants` / `test_text_nav_invariants_all` to the function table in
  [documentation/testing.md](../../documentation/testing.md) — it is currently absent, so there is
  no discoverable entry point for the linear cursor walk.
- If Step 2/3 turned up reader bugs, note the coverage status in
  [documentation/architecture.md](../../documentation/architecture.md) next to the existing
  keyboard-navigation row.

## Findings

### The raw-vs-stripped question is moot: compare carets, not paths

Neither raw nor stripped path strings can be compared across directions, and the reason is by
design. `_step_left` and `_step_right`
([Text.jl:320-344](../../package/visual/main/text/Text.jl#L320-L344)) each skip the *boundary
duplicate*: at a span boundary the one visual caret has two equally valid paths, `(span, len)` and
`(span + 1, 0)`. `right` canonicalizes to the first, `left` to the second. So the two walks
necessarily produce different path sequences over the same carets, and X3/X4 on paths could never
have held. `_walk_cursor` therefore also records the **rendered caret rect** of each state, and the
cross-direction comparison is about carets.

Exact caret equality is still too strict, though: at a *line* boundary the two representatives
render in different places — end of line N versus start of line N+1, the same ambiguity
`test_click_roundtrip` already tolerates with its one-band `dy` slack. Caret-sequence equality
therefore holds only for single-line texts (`text`, `json_string`, `primitive_string`) and is **not
asserted**. What is asserted instead:

- **same_length** — the two walks visit the same number of carets.
- **right_reaches_end** — the rightward walk's terminal state is where Ctrl+End lands (X1).
- **left_reaches_start** — the leftward walk's terminal state is where Ctrl+Home lands (X2).

Together these say "walking left from the end retraces the rightward walk and arrives at the start",
which is the property the test was missing.

### The bug: `left` stalls on projection-introduced text

**The leftward walk collapses on every syntax-backed document.** It gets two or three steps in from
the end and stops:

| example | right | left | same_length | right_reaches_end | left_reaches_start |
|---|---|---|---|---|---|
| json | 348 | **3** | ❌ | ✅ | ❌ |
| json_insertion | 15 | **7** | ❌ | ✅ | ❌ |
| syntax | 84 | **3** | ❌ | ✅ | ❌ |
| focusing | 26 | **3** | ❌ | ✅ | ❌ |
| sql_syntax | 29 | **2** | ❌ | ✅ | ❌ |
| sql_insert_syntax | 51 | **3** | ❌ | ✅ | ❌ |
| dragging | 68 | **3** | ❌ | ✅ | ❌ |
| markdown | 395 | **11** | ❌ | ❌ | ❌ |
| formula | 32 | **4** | ❌ | ❌ | ❌ |
| sql_update_syntax | 48 | **7** | ❌ | ❌ | ❌ |
| json_null | 6 | 6 | ✅ | ✅ | ✅ |
| json_string | 15 | 15 | ✅ | ✅ | ✅ |
| text | 449 | 449 | ✅ | ✅ | ✅ |
| plain_text | 202 | 202 | ✅ | ✅ | ✅ |
| text_with_image | 199 | 199 | ✅ | ✅ | ✅ |
| text_filtering | 209 | 209 | ✅ | ✅ | ✅ |
| text_highlighting | 209 | 209 | ✅ | ✅ | ✅ |
| primitive_string | 15 | 15 | ✅ | ✅ | ✅ |

(Skipped by the sweep, unchanged: 7 examples that already fail to print or seed — `json_sorted`,
`yaml`, `mixed`, `markdown_rendered`, `searching`, `graph`, `sql_nested_syntax` — and 8 with no
cursor at the top of their pipeline.)

**Diagnosis.** Walking left from the end of the `syntax` example goes
`close{1}` → `close{0}` → `SyntaxNodeProjectionReference(…Position{82})`, and there it **clamps in
place**: `left` returns the selection it was given, while `right` from that same state advances
normally. That state is a caret sitting on *projection-introduced* text — the flat-offset position
`SyntaxToText` emits for its own indentation/markers, rather than a position inside a domain node.
`_text_char_motion` clamps exactly when `_step_left` returns `nothing`, which happens only at
(first span, char 0), so the forward map is placing that introduced-text caret at the *start* of the
text rather than where it renders. Rightward motion never exercised this, because the only
end-to-end walk in the suite ran left-to-right — which is precisely the gap this plan set out to
close.

The pure-text examples are unaffected (they have no projection-introduced spans), which is why the
walk is symmetric exactly for them.

**Not fixed here.** The fix belongs in the `SyntaxToText` forward map, not in a test, and its blast
radius is a reader change across every syntax-backed domain. The ten affected examples are marked
`@test_broken` with a `# @broken:` note, so the suite records the breakage instead of hiding it, and
the follow-up is [left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md).

### Incidental fixes made to test helpers

- `_find_text_iomap` iterated `step_iomaps` / `child_iomaps` without checking for `nothing`, and
  threw on any pipeline with an unexpanded node. It now skips absent children.
- Probing the caret forces graphics cells that a bare `print_document` leaves lazy, so a printer
  error can surface there; the caret probe is guarded like the print itself.
- The walk guards the printer and readers, so the 7 examples that cannot print now report a clean
  `Fail` instead of throwing out of the testset as an `Error`.
