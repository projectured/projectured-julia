# JuliaToSyntax — bidirectional cursor navigation

> **Status (2026-08-12): IN PROGRESS.** Structural-token navigation (the problem
> this plan opens with) is fixed — but by a different mechanism than the plan
> proposes: `JuliaToSyntax.jl` was rewritten with `@projection_template`
> (commits `a764d510`, `962bc361`, `bf8de12a`, 2026-07-02), which gets reference
> mapping for free from the shared `RuleIoMap` machinery, plus a caret-round-trip
> follow-up in [julia-navigation-caret-roundtrip.md](../done/julia-navigation-caret-roundtrip.md)
> (`plan/done/`, commit `43ec6e7`). `explore_position_selections` on `julia_example`
> now reaches 82 states (was ~3), and `test_position_navigation(julia_example;
> check_reaches_all=true)` runs 84 pass / 28 fail / 0 error. The 28 remaining
> failures are exactly this plan's Step 3 (the `name` vs `value` leaf field-name
> mismatch) — still open, and now the only remaining piece.

**Origin:** Follow-up to the D/High finding in
[plan/done/consistency-report.md](../done/consistency-report.md). Filed 2026-06-15.

## Problem

`JuliaToSyntax`'s 30 sub-projections define `projection_print` but rely on the
generic `Projection` defaults for `map_reference_forward` / `map_reference_backward`
/ `projection_read`. As a result keyboard navigation into nested Julia is broken:
`explore_selections(julia_example)` reaches only ~3 states for an entire
`factorial` function (it never descends into the name / params / body), because the
cursor cannot rest on or traverse *through* the projection-introduced structural
tokens (`function`, `(`, `)`, `==`, `*`, `-`, `if`, `else`, `end`, …).

## What was tried (and reverted)

A full School-A mapper set (per-node `map_reference_forward`/`_backward` +
`projection_read`, with the node printers' selection cells wired via the
deferred-iomap trick, mirroring `JsonToSyntax`) was implemented and verified to
compile and print (`test_printer(julia_example)` = 1755 checks, no errors). It was
**reverted** because content mappers alone do not restore navigation: they leave
the cursor unable to traverse structural tokens, and the whole-element fallback for
the `name`-field leaves (`JuliaIdentifier`/`JuliaSymbol`) and content-less keyword
leaves nudged the reachable-state count *down* (3 → 2) rather than up. See the
commit history around `JuliaToSyntax: document deferred reference mapping`.

## The actual missing piece

`JsonToSyntax` makes structural positions navigable with a flat-offset
projection-reference mechanism (`_syntax_to_flat`, in `SyntaxToText`): a structural
output position with no input pre-image is mapped back to
`proj(p, PositionReference(flat))`, a single flattened character offset that the
`SyntaxNode` renderer/navigator understands and that round-trips. `JuliaToSyntax`
has no equivalent, so its structural tokens are dead ends for the cursor.

## Plan

- [x] ✅ DONE (2026-08-12), by a different mechanism than proposed: structural
      positions are navigable, but not through a reused `_syntax_to_flat` helper.
      `JuliaToSyntax.jl` was rewritten to use `@projection_template` for all 32
      sub-projections (commits `a764d510`, `962bc361`, `bf8de12a`, 2026-07-02),
      which get reference mapping and reading for free from the shared `RuleIoMap`
      machinery in `package/kernel/main/projection/ProjectionTemplate.jl`
      (generic `map_reference_forward`/`map_reference_backward` at lines 732/745).
      A follow-up, [julia-navigation-caret-roundtrip.md](../done/julia-navigation-caret-roundtrip.md)
      (`plan/done/`, commit `43ec6e7`), then fixed introduced-token caret
      round-tripping in `ProjectionTemplate.jl`'s `_slots_forward`/`_slots_backward`
      and `document/Syntax.jl`'s `_tree_navigate`.
      <!-- Old finding (2026-06-23, now superseded): JuliaToSyntax.jl defined no
      projection_read for any Julia node; `_syntax_to_flat` (SyntaxToText, now
      `package/syntax/main/SyntaxToText.jl`) was mentioned only in a comment, never
      used. That approach was not the one taken. -->
- [x] ✅ DONE (2026-08-12), by a different mechanism than proposed: not hand-written
      School-A `map_reference_forward`/`map_reference_backward` per node — the
      `@projection_template` rewrite (see above) gets this generically from
      `RuleIoMap`, so no per-node mapper code was needed for content positions
      either. Verified live: `explore_position_selections(julia_example.document,
      julia_example.projection).state_count == 82` (was ~3), and
      `test_position_navigation(julia_example; check_reaches_all=true)` runs
      84 pass / 28 fail / 0 error — the 28 failures are exactly Step 3 below.
- [ ] ⏳ OPEN (confirmed 2026-08-12): Resolve the leaf field-name mismatch.
      `JuliaIdentifier`/`JuliaSymbol` store their text in `name` (not the SyntaxLeaf
      `value`), and `JuliaNothing`/`JuliaBreak`/`JuliaContinue` have no text field.
      This is now the *only* remaining piece: the 28 `test_position_navigation`
      failures are exactly `…name{k}` unreached carets (e.g.
      `.body.statements[1].else_branch.statements[1].right.callee.name{8}`), and
      `JuliaToSyntax.jl`'s own comment (around lines 873-894, file now 1025 lines)
      says the leaves are still opaque — no `bound(…)` marker — and names this as
      the deferred follow-up. JSON's leaves (`package/json/main/JsonToSyntax.jl`)
      use `bound(:value, Type, ...)` inside `@projection_template`; Julia's
      identifier/symbol leaves do not use `bound(...)` at all — that omission is
      the concrete fix still needed. The old "without touching `Operation.jl`"
      framing no longer applies — `common/Operation.jl` does not exist any more
      (see Notes).
- [~] IN PROGRESS (2026-08-12): Verify with `test_position_navigation(julia_example;
      check_reaches_all=true)` / `test_tree_navigation` (the plan's cited
      `test_selection(julia_example)` never existed under that name — both live in
      `package/substrate/test/editor/NavigationPresets.jl`) and `test_repl` (`package/kernel/test/editor/ReplTest.jl:102`).
      Reachable-state count has grown well past the old 3 (82 states, 0 errors), but
      is not fully green until Step 3 lands (28 fail, all `…name{k}` carets). Note
      the kernel-wide rename: `projection_print`→`print_document`,
      `projection_read`→`read_intent` (commit `fa2b1a4d`, 2026-07-03).

## Notes

- **✅ DONE (verified 2026-06-23, guard since relocated):** During investigation a
  latent crash was found: `set_selection!` / `clear_selection!` throw a `FieldError`
  when a path step names a field the document lacks. A one-line `hasfield` guard
  fixes it generally, but `Operation.jl` was off-limits at the time — that
  constraint has since lifted, and the guard has moved with the code: `common/Operation.jl`
  no longer exists (the kernel gained a dedicated `selection/` layer, commit
  `64578e82` "Extract a selection layer"); the two duplicate guards were deduped
  into one shared helper, `_selection_child`, at
  `package/kernel/main/selection/SelectionDefaults.jl:322`
  (`hasproperty(document, sym) || return nothing`), called by `clear_selection!`
  (line 51), `_set_selection_walk!` (line 195), and `_sync_selection!` (lines
  277-278/296-297/304). (This fixes the crash but does not implement the
  navigation feature — Step 3 above remains the open item.)
