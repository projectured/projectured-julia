# A type in a pattern narrows the match

`@reference_case` treats a `::T` checkpoint as documentation: it never fails a
match. This plan makes it **narrow where the reference carries a type, and stay
silent where it carries none**, so a pattern can speak of every node of a kind
rather than every node at a place.

## Why

`queue::PacketQueue.capacity` reads as "the capacity of a `PacketQueue`" and
matches any queue-shaped path today, whatever the node actually is. Selecting by
kind is the point of writing a type in a pattern, and without it every selector
has to fall back on the lower-case bind plus a guard —
`when(queue::t, t <: PacketQueue)` — which says the same thing three times.

It also restores a tripwire the folded model lost. Before type checkpoints were
folded into node fields, a leading `TypeReferenceStep` made a cross-domain path
fail to match structurally; folded, nothing stops a stale or foreign selection
from matching a pattern it has no business matching.

## Behaviour before the change

`package/kernel/main/reference/ReferenceCase.jl`, as of `4d599bf0`:

- `PatStepType` (line 82) is the capitalised `::T` assertion; `PatStepTypeBind`
  (line 90) is the lower-case `::t` binder, which stays exactly as it is.
- `_gen_path_match` (line 349) intercepts a leading `PatStepType` at line 370 and
  emits *no check at all*: it matches the rest of the pattern against the same
  path for a folded node, or against `tail` when an unfolded `TypeReferenceStep`
  step is present. `_gen_prefix_match` (line 434) does the same at line 451.
- The comment above each branch states the intent — "an OPTIONAL, non-navigating,
  *tolerant* assertion … never causes a match to fail" — and gives the reason:
  "an enforcing `<: T` gate here wrongly rejects re-rooted child selections whose
  folded node type differs from the documented one".

That reason came from commit `5f75c0ec` (25 Jun), which reverted an enforcing
gate after it broke the navigator's click-on-file repl.

## Why the June regression does not come back

**This section was wrong as planned; the implementation corrected it.** The
enforcing gate `5f75c0ec` reverted was *already* `nothing`-tolerant:

```julia
local _nt = sp isa ConcreteReferencePath ? sp.type : …
(_nt === nothing || _nt <: ty) ? rest_on_same : _nomatch
```

So "re-rooted paths carry no type" does not explain the June breakage away — that
gate tolerated exactly those paths and broke the navigator repl anyway. The commit
message says the rejected paths were re-rooted child selections "whose folded node
type **differs** from the documented one", which is a different claim.

What actually made it safe is the *other* fix in that same commit: `_selection_child`
was doing a raw `getfield` with no `hasproperty` guard, and that guard is still in
place today. The tolerance revert was collateral.

Measured rather than argued, before anything was committed — the gate applied as a
throwaway patch, the four suites and the navigator/filesystem/workbench repls run
against a recorded pre-change baseline:

- **zero** changed test outcomes; output byte-identical modulo timing and RNG seeds;
- instrumenting the predicate across visual+domain: **9514** typed paths admitted,
  **4191** untyped tolerated, **10** rejected, 0 non-`Type` values — so the gate is
  load-bearing, not inert;
- all 10 rejections at one site, `ChartPlotToGraphics._reference_series_index`, whose
  own comment already said its two arms are a `ChartPlot`-rooted reference and a
  `Chart`-rooted one. Tolerant, arm 1 fell through to arm 2 only because
  `.chart.series[i]` does not fit `.series[i]` structurally. Narrowing separates them
  by the root type the comment names: same answer, stated reason.

## The change — done

`ReferenceCase.jl` is sealed; permission was given in the implementing conversation
(2026-08-06) on the "measure first" condition recorded above.

1. **Done.** `_gen_path_match`'s `PatStepType` branch gates on
   `_type_step_matches(nodetype, T)`, keeping both continuations — the same path for a
   folded node, `tail` for an unfolded `TypeReferenceStep` step.
2. **Done**, and wider than planned. Between this plan being written and being
   implemented, `main` gained `@reference_rules` (`ReferenceRules.jl`), an
   *interpreter* over the same `PatStep` AST. The step therefore has **four**
   readings, not two — `_gen_path_match` / `_gen_above_match` compiled, `_consume` /
   `_match_above` interpreted — and all four call the one predicate, which is what
   the plan's "must not drift" asked for.
3. **Done.** `PatStepTypeBind` untouched.
4. **Done.** `_type_step_matches` carries the whole rule and its reasoning in one
   place, so no reader can restore tolerance from the old rationale.

A non-`Type` recorded value is tolerated alongside `nothing`: `<:` throws a
`TypeError` on one, and a crash inside a matcher is worse than a match. The
instrumentation counted 0 of these, so that branch is defensive only.

### Also done on this branch — `prefix` retired

Requested during implementation, not part of the original plan.
`@reference_case`'s `prefix(P)` held when the input ran out *inside* `P` — i.e.
`above(P)` — while reading as though it meant `at_or_below(P)`. Both DSLs now speak
the five arm words `@reference_rules` introduced (`at`, `below`, `at_or_below`,
`above`, `at_or_above`), with `REFERENCE_RULE_MODES` moved to `ReferenceCase.jl`
beside the shared AST so the vocabulary has one definition. `_gen_path_match` takes
which leftover it is asked for and reads it only where the pattern runs out;
`_gen_prefix_match` becomes `_gen_above_match` with an `include_at` flag, and
`at_or_above` falls out as above-or-at. The extension-step seam still calls the
four-argument form, which is `at`. Writing `prefix(…)` in either DSL is an error
naming both replacements, since neither is the obvious one. Two production arms
migrated — `ReferenceDispatching` and `HigherOrderCompound` — and both meant `above`.

## Documentation — done

- `package/kernel/doc/reference.md` — the cross-DSL table gained a `::T` row; a new
  section, "A type in a pattern narrows the match", states the rule, the silent case
  and why each untyped path is untyped; the `@reference_case` section replaces its
  `prefix(…)` paragraph with the five-word arm table, and the `@reference_rules` one
  now points at it rather than restating it.
- The `@reference_case` docstring's closing paragraph — "A `::T` checkpoint is a
  **tolerant** assertion … never fails a match", the sentence this plan falsified —
  states the narrowing rule instead, and the arm table replaces the `prefix` line.
- The `@reference_rules` docstring gained the narrowing sentence and dropped its
  "`above(P)` is what `@reference_case` spells `prefix(P)`" note, which no longer
  describes anything.
- `ReferenceBuilderTest.jl`'s "capitalized `::T` stays a (tolerant) assertion"
  comment now says narrowing.

## Tests — done

`package/kernel/test/reference/ReferenceEvalTest.jl` (7 -> 33 assertions):

- a pattern whose `::T` matches the annotated node type — matches;
- the same pattern against a path annotated with an unrelated type — no match,
  and the *next* arm gets its chance;
- a pattern naming a supertype against a path annotated with a concrete subtype
  — matches;
- a pattern with `::T` against a path built by `reroot_reference` (type
  `nothing`) — matches, which is the June regression as a test;
- the same four through `above(…)`, so the above-matcher is covered;
- `∅::T` against a typed and an untyped whole-element selection.

`package/kernel/test/reference/ReferenceRulesTest.jl` (+52) covers the interpreted
side. Two entries join the conformance corpus, which already carries a
`RulesA`-typed and a `RulesOther`-typed path of the same shape so an arm per type is
decided by the node type alone. Conformance *alone* cannot catch a regression here —
it would still pass if both readings went back to tolerating everything — so a
separate testset asserts the answers, across all five modes.

Both files also gained an arm-vocabulary testset: one pattern, five forms, over paths
above / at / below it, plus the `prefix(…)` rejection.

## Verification — done

Run from the repo root environment (worktree
`/home/projectured/workspace/projectured-julia-narrowing`, branch
`reference-case-type-narrowing`, rebased onto `main` at `27ca53bb`).

- `test_reference_eval()`, `test_reference_builder()`, `test_rerooting()` first.
- Then `test_kernel()`, `test_base()`, `test_visual()`, `test_domain()`.
- Then the navigator repl the June commit named as its evidence — a
  click-on-file run — since that is the surface the enforcing gate broke.
- Cap memory as usual: run under `systemd-run` with a `MemoryMax`.

Result: **no new failures anywhere.** Against the recorded baseline, base / visual /
domain are identical (387P; 49534P 1 broken; 184679P 5 broken) and the kernel's
471 -> 970 pass count is entirely the rebase picking up `ReferenceRulesTest` plus the
new tests, with its 3 fails / 2 errors the pre-existing `DocumentMacro` "Rule C"
ones. The navigator, filesystem and workbench repls are 224/1 before and after, that
one failure being pre-existing.

None of the three budgeted risks materialised:

- patterns naming a type from the wrong side of a projection (input where the
  path is output-rooted, or the reverse);
- cross-domain stale selections that used to match silently and now fail, which
  is the tripwire being restored rather than a defect;
- anywhere a pattern documents a concrete type while the path records a
  supertype — those fail, and the pattern is what is wrong.

The one site that did change behaviour is the chart mapper above, and it is the
tripwire working rather than a defect. The gate was not loosened.

## Done

All four matcher readings narrow through one predicate; the cases are tested through
both the at-family and the above-family, in the compiled and the interpreted DSL; the
guide, both macro docstrings and the `ReferenceBuilderTest` comment state the rule;
and the four package suites plus the navigator repls are green with no new failures
against a baseline recorded before the change.

Commits: `c2b1d232` (narrowing), `f4dc0d21` (arm vocabulary, `prefix` retired).
