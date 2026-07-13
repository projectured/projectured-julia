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

### Step 1 — factor out a direction-parameterized walk

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

### Step 2 — add the leftward walk, and measure

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

### Step 3 — cross-direction invariants

Add X1, X2, X3 as `@test`s. Add X4 too, but gate it on what Step 2's table showed: where the order
reversal genuinely fails because of the line-boundary path ambiguity, mark it `@test_broken` with a
`# @broken:` comment naming the example and the ambiguity (per the repo's
"Marking known-failing tests" convention), rather than deleting the assertion.

If X3 fails for an example, that is a real direction-asymmetry bug in a reader — stop and
investigate it before marking anything broken. Record the diagnosis here.

**Verify:** the sweep again; `Fail`/`Error` must stay at zero, and any change in the `Broken` count
must be explained by a `# @broken:` marker added in this step.

### Step 4 — docs

- Update the `ClickRoundtripTest.jl` header comment: `test_text_nav_invariants` now walks both
  directions and cross-checks them. (Describe what it *is*, not that it changed.)
- Add a row for `test_text_nav_invariants` / `test_text_nav_invariants_all` to the function table in
  [documentation/testing.md](../../documentation/testing.md) — it is currently absent, so there is
  no discoverable entry point for the linear cursor walk.
- If Step 2/3 turned up reader bugs, note the coverage status in
  [documentation/architecture.md](../../documentation/architecture.md) next to the existing
  keyboard-navigation row.

## Findings

_(fill in during implementation — measurement table from Step 2, any direction-asymmetry bugs found
in Step 3, and the resolution of the raw-vs-stripped path-string question.)_
