# Printer locality — session archive / handoff

Archive of the working session that started the printer-locality plan. This is
the conversation-level record (what happened, what was decided, where to
resume); the technical audit is in
[printer-locality-findings.md](printer-locality-findings.md) and the plan in
[printer-locality.md](printer-locality.md).

## Request

> "Create a plan to check the locality of printers — printers should produce the
> smallest possible change in their output for any given input. Especially true
> for selection handling. There are probably exceptions, but they have to be
> justified." Then: "start the plan, work in a worktree, commit along the way."

## What was produced (branch `claude/printer-locality-plan-rbzmq5`)

| Commit | What |
|---|---|
| `5a735d3` | The plan — `plan/pending/printer-locality.md` (3 locality dimensions, harness, audit, fix-vs-exception, lock-in). |
| `2402bf6` | Phase 1 — `package/test/src/editor/PrinterLocalityTest.jl`: `printer_locality_report` + dimension A (selection) driver. |
| `ada35a0` | Phase 2 — dimension C (structural) driver; dimension A scope fix. |
| `a72d6b2` | Phase 3 (partial) — static engine audit, `printer-locality-findings.md`. |
| `1335a07` | Phase 2 — dimension B (value) driver. Completes the 3-dimension harness. |

Public API (exported from `ProjecturedTest`): `printer_locality_report`,
`explore_selection_locality` / `test_selection_locality` / `test_selection_localities`,
`explore_value_locality` / `test_value_locality` / `test_value_localities`,
`explore_structural_locality` / `report_structural_locality`,
plus `LocalityReport`, `LocalityCell`, `is_selection_cell`.

## The three dimensions (as built)

- **A — selection isolation.** A pure `set_selection!` must invalidate ONLY
  `:selection`-tagged output cells. Measured by the **invalidation set**.
- **B — value-edit isolation.** Perturbing one scalar leaf must rebuild NO output
  object. Measured by `lost_objects == 0` (assertion).
- **C — structural minimality.** Inserting one element must preserve unaffected
  siblings' output objects. Measured by **object-identity loss** (report only —
  the engine is known non-local here; Phase 4 decides fix-vs-exception first).

## Key decisions / rationale (so they aren't re-litigated)

- **Why two different measures.** The reactive engine is write-driven with no
  equality check, and a rebuilt slot cell is *orphaned*, not *invalidated*. So
  invalidation captures A/B; object-identity loss captures C. A single measure
  would miss one or the other.
- **Dimension A measured by invalidation, NOT identity** — caught mid-build: a
  selection cell legitimately recomputes to a *fresh* `ReferencePath`, so
  `lost_objects > 0` is expected for a selection move and must not be flagged.
- **Dimension A scope limit.** Exact for projections that carry selection as a
  `:selection` field (syntax/widget/structural layers — most printers). A full
  pipeline to graphics lowers the caret into geometry cells not named
  `:selection`; those need a cursor-field allow-list before the check is exact —
  noted as a Phase 2 follow-up. This is why the locality tests are NOT wired into
  `test_all` yet.
- **Static audit (Finding 2) is the headline.** `ProjectionTemplate.jl:283,303`:
  `CellVector(() -> [...])` recreates every slot cell and `child_iomaps`
  re-projects every sibling on any structural edit → siblings lose identity.
  Candidate fix: keyed reconciliation by element `objectid`.

## Blocker (why the plan is not finished)

**No Julia toolchain in the session environment, and the network was locked
(403 on package fetches).** The harness could not be executed, so:
- all harness code is committed but **runtime-unverified** (commit messages say so);
- the Phase 3 audit table (running the sweep over ~90 examples) is **not done**;
- the Phase 4 keyed-reconciliation engine fix was **deliberately not attempted**
  blind — it rewrites the core every printer depends on and the plan flags it as
  the riskiest part.

## Resume here (next agent, with a runtime)

1. `using Projectured, ProjecturedExample, ProjecturedTest`.
2. Sanity-run the harness on one example and fix any harness bugs the static
   review missed: `test_selection_locality(json_example)`,
   `test_value_locality(json_example)`, `report_structural_locality(json_example)`.
3. Sweep and record the audit table: `test_selection_localities()`,
   `test_value_localities()`, and `report_structural_locality` over all examples.
   Confirm the predictions in `printer-locality-findings.md` (Finding 1 → A/B
   pass for structural layers; Finding 2 → C ≈100% churn engine-wide).
4. Build the cursor-field allow-list so dimension A is exact for graphics pipelines.
5. Phase 4: implement keyed reconciliation in `_node_print` / `_mixed_print` /
   `_sections_print`; verify behavior is unchanged with `test_example(json_example)`
   / `test_example(xml_example)` and `test_text_navigation(...; check_reaches_all=true)`.
6. Phase 5: promote to `test_printer_locality` + encode the justified-exception
   list as data; document the principle in `documentation/projection-system.md`
   and the `projection_print` docstring.

## Housekeeping note

A redundant remote branch `claude/printer-locality-impl` (identical commit to the
designated branch) could not be deleted — the environment's git proxy blocks ref
deletions. Harmless; delete from a normal environment with
`git push origin --delete claude/printer-locality-impl`.
</content>
