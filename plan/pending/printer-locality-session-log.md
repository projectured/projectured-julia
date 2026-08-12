# Printer locality — session archive / handoff

> **Status (2026-08-12): SUPERSEDED (historical record only).** Branch
> `claude/printer-locality-plan-rbzmq5`, named below, no longer exists — but its
> work reached `main`: the plan, the Phase 1/2 harness, and the Phase 3 static
> findings all merged, and further work (both a Phase 4 selection-isolation fix
> and a Phase 4 keyed-reconciliation engine fix) has since landed on top of it.
> Current status lives in [printer-locality.md](printer-locality.md) and
> [printer-locality-findings.md](printer-locality-findings.md); read this file
> only for the history of how the harness got built.

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

## What was produced (branch `claude/printer-locality-plan-rbzmq5`, now deleted)

The branch itself is gone and these exact commit hashes are not ancestors of
`main` — the content landed on `main` through a rebase/re-commit under new
hashes (`75604bbb`, `60141931`, `3b77ee53`, …), same messages. The table below is
kept as the historical record of what this session did; see
[printer-locality.md](printer-locality.md) for what is true on `main` today.

| Commit | What |
|---|---|
| `5a735d3` | The plan — `plan/pending/printer-locality.md` (3 locality dimensions, harness, audit, fix-vs-exception, lock-in). |
| `2402bf6` | Phase 1 — `package/projectured/test/editor/PrinterLocalityTest.jl` (path as landed on `main`; the plan's own body still says `package/test/src/editor/PrinterLocalityTest.jl`, which never existed): `printer_locality_report` + dimension A (selection) driver. |
| `ada35a0` | Phase 2 — dimension C (structural) driver; dimension A scope fix. |
| `a72d6b2` | Phase 3 (partial) — static engine audit, `printer-locality-findings.md`. |
| `1335a07` | Phase 2 — dimension B (value) driver. Completes the 3-dimension harness. |

Further work landed on `main` after this session, not reflected in this log:
`0c2423c6`/`29b04eef` (Phase 4 selection-isolation fixes, widget layer) and the
generic `reconcile_child_iomaps` engine fix (Phase 4 structural fix, wired into
`_node_print`) plus `03c72774` (`SyntaxNodeToText` delegation, closing a Finding
4 justified-exception item).

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

## Blocker (why the plan was not finished in this session — RESOLVED since)

**No Julia toolchain in the session environment, and the network was locked
(403 on package fetches).** The harness could not be executed, so:
- all harness code was committed but **runtime-unverified** (commit messages said so);
- the Phase 3 audit table (running the sweep over ~90 examples) was **not done**;
- the Phase 4 keyed-reconciliation engine fix was **deliberately not attempted**
  blind — it rewrites the core every printer depends on and the plan flagged it as
  the riskiest part.

A Julia toolchain is available in the repository's normal working environment.
The harness runs (confirmed 2026-08-12), and the keyed-reconciliation fix was
attempted and landed — see [printer-locality.md](printer-locality.md) for what
is done and what is still open.

## Resume here — most of this list is now either done or superseded; see [printer-locality.md](printer-locality.md) for the current per-item status

1. ~~`using Projectured, ProjecturedExample, ProjecturedTest`.~~ Done — this is
   the normal way to load the umbrella test package.
2. ~~Sanity-run the harness on one example and fix any harness bugs the static
   review missed: `test_selection_locality(json_example)`,
   `test_value_locality(json_example)`, `report_structural_locality(json_example)`.~~
   Done. No harness bugs found; `json_example` (the full pipeline) fails
   wholesale on dimensions A/B, which is the documented scope gap, not a bug.
3. Sweep and record the audit table: `test_selection_localities()`,
   `test_value_localities()`, and `report_structural_locality` over all examples.
   **Still open** — running these today fails wholesale on full-pipeline
   examples until item 4 is done, so no table has been produced. Finding 2's
   prediction (C ≈100% churn engine-wide) was confirmed, then fixed for
   `_node_print` only.
4. Build the cursor-field allow-list so dimension A is exact for graphics
   pipelines. **Still open.**
5. Phase 4: implement keyed reconciliation in `_node_print` / `_mixed_print` /
   `_sections_print`. **Done for `_node_print` only** (`reconcile_child_iomaps`
   in `package/kernel/main/iomap/IoMapReconcile.jl`); `_mixed_print` /
   `_sections_print` were not converted. Verifying behavior is unchanged with
   `test_example(json_example)` / `test_example(xml_example)` and
   `test_position_navigation(...; check_reaches_all=true)` (the plan's
   `test_text_navigation` does not exist) is **not done** as part of this audit.
6. Phase 5: promote to `test_printer_locality` + encode the justified-exception
   list as data; document the principle in `documentation/projection-system.md`
   and the `projection_print` docstring. **Still open** — see
   [printer-locality.md](printer-locality.md) Phase 5 for what exists under
   different names instead.

## Housekeeping note

A redundant remote branch `claude/printer-locality-impl` (identical commit to the
designated branch) could not be deleted at the time — the environment's git proxy
blocked ref deletions. Resolved: neither `claude/printer-locality-plan-rbzmq5` nor
`claude/printer-locality-impl` exists on `origin` any more (checked 2026-08-12).
</content>
