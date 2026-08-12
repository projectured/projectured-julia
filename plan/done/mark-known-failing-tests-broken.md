# Mark all currently-failing test assertions with `@test_broken`

> **Status (2026-08-12): DONE.** Every item in the "Deferred" list below is now
> resolved, either fixed outright or `@test_broken`/`@test_skip` with a per-example
> marker, confirmed against the current suites. Phase 7 (plan retirement) is no
> longer blocked; this plan is ready to move to `plan/done/`.

## Status (2026-07-07, resolved 2026-08-12)

- ✅ Phase 1 — Baseline captured.
- ✅ Phase 2 — Domain sweep (26 markers). `test_domain()` clean: 134644 Pass / 26 Broken / 0 Fail / 0 Error.
- ✅ Phase 5 — Convention documented in `documentation/testing.md` (the "Marking
  known-failing tests" section, confirmed present).
- ✅ Phase 6 — `CLAUDE.md` nudge added (confirmed present, line ~195: "An unmarked
  `Fail` or `Error` is a regression from your change…").
- ✅ DONE (2026-08-12) — Phase 3 — Umbrella sweep. All items below resolved; see
  "Deferred" section, now annotated with the commit that closed each one.
- 🟡 Phase 4 — Opt-in sweep **partial** (not re-verified in this pass; last measured
  2026-07-07):
  - `test_sdl()` 30/30 clean; `test_tulip()` 14/14 clean.
  - `test_video()` VideoTest.jl 2 testsets wrapped → `@test_broken`.
  - `test_odbc()` 102 Pass / 7 Broken / 0 Fail / 0 Error — live-DB paths wrapped, T5 show-string markers added, cleanup FK errors swallowed.
- ✅ DONE (2026-08-12) — Phase 7 (plan retirement) — no longer blocked; every
  Deferred item is resolved.

## Deferred (Option B tail) — all items resolved 2026-08-12

The umbrella `test_all()` used to surface unmarked failures because each of
these four umbrella sweeps fanned a single failing example over its whole
example registry. Current state of each, confirmed against the code:

- `test_printers()` / `test_readers()` — **✅ DONE (2026-08-12).** `json_sorted`
  is fixed outright, not just marked: commit `afa1c927` ("json_sorted prints
  normally now, drop its @test_broken", 2026-07-15). `package/projectured/test/editor/ExampleSweeps.jl`
  now runs it unmarked and clean.
- `test_repls()` — **✅ DONE (2026-08-12).** `json_sorted`, `sql_update_syntax`
  (and the stack-overflow-inducing `focusing`/`xml`, still `@test_skip`'d) are
  covered by a `repl_broken(name)` predicate added in commit `4868e704`
  ("mark the known reader/repl failures @test_broken", 2026-07-15), in
  `package/projectured/test/editor/ExampleSweeps.jl:75-91`.
- `test_text_navigations()` — **✅ DONE (2026-08-12), superseded.**
  `TextNavigationTest.jl` no longer exists; it was replaced by a broader
  navigation-test architecture (`test_position_navigations()`,
  `test_tree_navigations()`, `test_text_nav_invariants_all()` in
  `package/projectured/test/editor/ExampleSweeps.jl`) built through mid/late
  July (commits `eb475113`, `c1337f07`, `fbe45557`). Of the original 8 examples,
  `json_sorted`/`line_numbering`/`conversation` now run unmarked and pass;
  `natural`/`filesystem`/`navigator`/`conversation_editor` are `@test_broken`
  via `posnav_seed_broken`; `rotating_vector` is `@test_broken` via `nav_broken`.
  All 8 are accounted for — none is an unmarked `Fail`.

Each needed a per-example broken-list in the sweep loop (same pattern used
in `test_domain_examples()`) — that is exactly what landed.

Also deferred, now resolved:

- `McpTest.jl:553` — **✅ DONE (2026-08-12).** Commit `9b9b0330` ("scratch
  namespace resolves domain names in per-layer test envs", 2026-07-07) fixed
  both the root-cause namespace bug and a genuine test typo (the assertion
  should check `"1"`, not `"2"`, since `arr[1]` is `JsonNumber(1)`). Current
  `package/projectured/test/editor/McpTest.jl:557-563` asserts `occursin("1", result)`
  with no marker needed.

## Purpose

Establish the invariant that **every known failure is annotated**, so an
unmarked `Fail` or `Error` in the summary is always a regression.

With this invariant, the standard `Test.jl` summary partitions failures for
free:

- `Pass / Fail / Error` columns → new / unexpected → regression signal.
- `Broken` column → previously catalogued, expected during transitional work.

No counts, no snapshot files, no bespoke tooling — the discipline replaces
all of them. This plan sets up the initial marking sweep and the ongoing
convention.

## Convention

**Every currently-failing assertion is wrapped with `@test_broken`.** The
annotation carries a one-line reason as a comment on the line above:

```julia
# @broken: SyntaxToText delegation refactor; helper _pos_to_selection removed
# see plan/text-projection-config-into-document.md
@test_broken sel.head isa ProjectionReference
```

Two failure shapes need different handling:

- **Assertion-level Fail or Error** — the throw or false comes from
  inside a `@test expr`. Replace the `@test` with `@test_broken`. This
  covers `Fail`s and most `Error`s.
- **Testset-setup error** ("Got exception outside of a @test") — the throw
  happens *before* an `@test` runs (e.g. constructor throws, `using` fails).
  `@test_broken` can't catch it because there's no assertion yet. Two options:
  - `@test_skip` on a stand-in assertion; the surrounding block guarded with
    `try/catch` so the setup exception is swallowed and the testset ends
    with a Skipped count instead of Error.
  - Refactor the setup into an `@test` call (`@test_broken (obj = f())`) so
    the throw becomes a broken assertion.

Prefer the first pattern (`@test_broken`) whenever possible — `@test_skip`
tests never run and rot silently. Reserve `@test_skip` for the rare cases
where running the code would crash the runner (stack overflow, infinite
loop, or corrupts subsequent tests).

### Comment format

Grep-friendly, one line, reason then optional plan-link:

```
# @broken: <one-line reason>[; plan/<slug>.md]
```

`grep -rn "@broken:"` gives the enumerable inventory. Every marker must
have a comment; a bare `@test_broken` with no context is a lint error
(enforced by convention, not a linter — for now).

## Baseline inventory (as of commit `6a01127`)

Ran with the current tree:

| suite                | Pass  | Fail | Error | Broken | notes |
|----------------------|-------|------|-------|--------|-------|
| `test_kernel()`      | 302   | 0    | 0     | 0      | already at target |
| `test_base()`        | 76    | 0    | 0     | 0      | already at target |
| `test_visual()`      | 51789 | 0    | 0     | 1      | already at target (pcp typing subtest) |
| `test_domain()`      | ~134644 | 19 | 7   | 0      | **the work** |
| umbrella `test_all()`|   ?   |   ?  |   ?   |   ?    | not measured yet |
| `test_sdl()`         |   ?   |   ?  |   ?   |   ?    | not measured (native dep) |
| `test_odbc()`        |   ?   |   ?  |   ?   |   ?    | not measured (native dep, live DB) |
| `test_tulip()`       |   ?   |   ?  |   ?   |   ?    | not measured (native dep) |
| `test_video()`       |   ?   |   ?  |   ?   |   ?    | not measured (native dep) |

The bulk of the work is in `test_domain()`. The opt-in and umbrella
suites need running before annotation — some of their failures may
overlap with the domain ones (drivers shared), others may be distinct.

## Enumerated domain failures to mark

From the last full run of `test_domain()` (26 items — 19 `Fail`, 7 `Error`):

**Kernel driver, hit via domain example:**
- `package/kernel/test/src/editor/PrinterTest.jl:138` — `json_sorted` fail

**Domain projections:**
- `package/xml/test/projection/XmlToSyntaxTest.jl:13` — error (likely testset-setup)
- `package/sql/test/projection/SqlToSyntaxTest.jl:112` — INSERT/UPDATE round-trip fail
- `package/projectured/test/projection/TableSelectionTest.jl:65,69,73,102` — 4 fails (highlight band + in-cell cursor)
- `package/projectured/test/projection/DraggingTest.jl:49,73,87,103` — 4 errors (press/drag/drop, sub-threshold, unresolvable, real pipeline)

**Domain editors:**
- `package/json/test/editor/JsonContentClicksTest.jl:28` — error (`json fixture`)
- `package/projectured/test/editor/McpTest.jl:250,463,464,537` — 4 items (`print_object` error; `workbench editor reference` 2 fails; `base_extensions` fail)
- `package/workbench/test/editor/AssistantMvpTest.jl:286,370,374,377,380,383,386,468,510` — 9 fails (collapse-on-header cluster + ScriptedLlm timestamps + Tool-use round-trip + layout)
- `package/projectured/test/projection/TableNavigationTest.jl:192` — `individual moves (3×3 with headers)` fail

Each of these needs an `# @broken:` line and a `@test_broken`. Reasons
should be short and honest — "unknown; predates the split" is fine when
we don't yet have a root cause.

## Phases

1. **Baseline capture (measurement).** Run each isolated suite —
   `test_kernel()`, `test_base()`, `test_visual()`, `test_domain()`,
   umbrella `test_all()` if it can be driven, and each opt-in test
   package that has its native dependency installed. Save the raw failure
   locations to `plan/pending/mark-known-failing-tests-broken.md` as a
   living appendix, or a scratch file we discard when the plan closes.
2. **Domain sweep.** For each of the 26 enumerated domain failures
   above, either:
   - convert `@test` → `@test_broken` with a `# @broken:` comment, or
   - reshape a setup-error case into an `@test_broken`-able form, or
   - if the assertion is genuinely testing behaviour that no longer
     applies (rare) — delete it with a comment referencing the removal.
3. **Umbrella sweep.** Same for umbrella `test_all()` failures once
   phase 1 has measured them.
4. **Opt-in sweep.** Same for `test_sdl()`, `test_odbc()`, `test_tulip()`,
   `test_video()` — only for the ones with the native dep installed.
   Un-installable suites are out of scope (nothing to observe).
5. **Convention document.** Add a short section to
   [documentation/testing.md](../../documentation/testing.md): the invariant
   ("every known failure is `@test_broken` with a reason"), the marker
   format, when to use `@test_skip` instead, and the grep command to
   enumerate.
6. **CLAUDE.md nudge.** Add one line under "Testing a change":
   *"An unmarked `Fail` or `Error` is a regression; a `Broken` count
   change is a status shift — read the comment on the marker."*
   This is the AI-facing side of the discipline.

## Success criteria

- Every measured suite exits with `Fail == 0`, `Error == 0`. Broken
  counts are whatever they are.
- `grep -rn "@broken:" package/*/test/src/` enumerates every marked
  test with its reason.
- The AI's "did my change regress" heuristic collapses to reading the
  standard summary — no `git checkout` bisection needed for the base case.

## Non-goals

- **Actually fixing** any of the marked failures. That is what each
  underlying plan (existing or future) is for.
- Introducing a `@test_pending` wrapper macro, snapshot file, or
  cross-suite count. Considered and rejected — `@test_broken` +
  discipline is sufficient (see the discussion that produced this plan).
- Marking flaky tests separately from known-broken ones. If a test is
  flaky, mark it `@test_broken` too and note "flaky" in the reason —
  we'll revisit if flakiness volume grows.
- Retrofitting historically-fixed markers (marks that predate the plan
  and are still in the tree). If they exist, leave them; the sweep is
  forward-looking.

## References

- Julia stdlib `Test.@test_broken` — semantics we rely on.
- `documentation/testing.md` — where the convention lives after phase 5.
- Existing marker in the tree: `package/visual/test/src/projection/ProjectionConfiguringTest.jl:106` (commit `f16ce8b`) — the shape all new markers should mirror.
