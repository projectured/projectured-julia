# Mark all currently-failing test assertions with `@test_broken`

## Status (2026-07-07)

- ✅ Phase 1 — Baseline captured.
- ✅ Phase 2 — Domain sweep (26 markers). `test_domain()` clean: 134644 Pass / 26 Broken / 0 Fail / 0 Error.
- ✅ Phase 5 — Convention documented in `documentation/testing.md`.
- ✅ Phase 6 — `CLAUDE.md` nudge added.
- 🟡 Phase 3 — Umbrella sweep **partial** (Option B from discussion):
  - Stack-overflow examples in `test_repls()` — `focusing`, `xml` — `@test_skip`'d (real runtime infinite recursion, not test drift).
  - Fanout-sweep broken-lists (`test_printers`, `test_readers`, `test_repls`, `test_text_navigations`) for `json_sorted`, `sql_update_syntax`, and the 8 TextNavigation examples — **deferred**. See "Deferred" below.
- 🟡 Phase 4 — Opt-in sweep **partial**:
  - `test_sdl()` 30/30 clean; `test_tulip()` 14/14 clean.
  - `test_video()` VideoTest.jl 2 testsets wrapped → `@test_broken`.
  - `test_odbc()` 102 Pass / 7 Broken / 0 Fail / 0 Error — live-DB paths wrapped, T5 show-string markers added, cleanup FK errors swallowed.
- ⏸ Phase 7 (plan retirement) — **blocked** on Deferred items below.

The plan stays in `plan/pending/` until Phases 3/4 are complete for the
umbrella.

## Deferred (Option B tail)

The umbrella `test_all()` still surfaces unmarked failures because each of
these four umbrella sweeps fans a single failing example over its whole
example registry:

- `test_printers()` — `json_sorted` fails once (already handled in
  `test_domain_examples()`, but this sweep runs it again).
- `test_readers()` — `json_sorted` fails once.
- `test_repls()` — `json_sorted`, `sql_update_syntax` still fail (the
  stack-overflow-inducing `focusing` / `xml` are skipped).
- `test_text_navigations()` — 8 examples fail at `TextNavigationTest.jl:146`:
  `json_sorted`, `natural`, `line_numbering`, `filesystem`, `navigator`,
  `rotating_vector`, `conversation`, `conversation_editor`.

Each needs a per-example broken-list in the sweep loop (same pattern used
in `test_domain_examples()`), or a driver-level `broken=true` keyword.
Estimated scope: ~4 short blocks + a shared broken-list constant, ~1
session.

Also deferred:

- `McpTest.jl:553` — `@test occursin("2", result)` on JsonArray indexing.
  Passes in domain env, fails in umbrella env — the test's `execute_julia_code`
  scratch namespace differs between the two. Needs either a robust
  assertion or an env-aware marker.

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
   [documentation/testing.md](../documentation/testing.md): the invariant
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
