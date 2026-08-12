# Get the complete test suite green

> **Status (2026-08-12): IN PROGRESS.** Items 1–7 are done. Of items 8–14, item
> 12 (table Alt+Down promote) is now also done — fixed by commit `cbdfdd4b` on
> 2026-07-18, after the last check of this plan. Items 8–11 and 13–14 still
> match a still-open root cause in the tree, though the test bookkeeping around
> them moved from scattered `@test_broken` markers into named broken-example
> registries in `ExampleSweeps.jl`. The package layout changed again on
> 2026-08-09 (commit `0ed5ed2f`, "Give every domain its own package"): every
> `package/*/src/...` path below moved to `package/*/main/...`, and
> `package/domain/` split into one package per domain — paths are corrected
> inline below.

<!--
AUDIT 2026-06-23 (verified against current codebase under package/*/src):
Items 1–6 and all sub-items of 7: DONE — code evidence cited inline below.
Items 8–14: OPEN — explicitly deferred by a documented scope decision; the
stubs/gaps they describe still exist in the tree (verified). Plan paths were
remapped from program/src → package/*/src.
OVERALL: HAS_OPEN_STEPS (8–14 remain). Keep in plan/pending.

AUDIT 2026-08-12 (re-verified after the 2026-08-09 per-domain package split):
paths remapped again, package/*/src → package/*/main (or package/*/test for
test files). Item 12 flipped to DONE (commit cbdfdd4b, 2026-07-18): the
TableNavigationTest.jl in-cell Alt+Down promote assertion is a plain @test now,
no @test_broken. Items 8, 9, 10, 11, 13 spot-checked against the current
symbols/files named below and still show the same open gap (renamed but not
fixed) — see notes per item. Item 14's JsonToSyntax has since been rewritten
onto @projection_template; the specific "line-117" reader quirk could not be
re-located under the new implementation and needs a fresh look, not a line
citation.
-->

`test_all()` on `main@8823a0a` reports **210158 passed, 1067 failed, 32 errored**
(figures as of 2026-06-23 — the test suite was not re-run for this update; see
[CLAUDE.md](../../CLAUDE.md), "do not run test_all blindly").
The failures collapse to a handful of root causes accumulated across the
keyword-constructor / ProjectionTemplate / TypeReference-checkpoint migration
series. Several were documented as "pre-existing" in recent commit messages.

## Root causes (by leverage)

1. **Text-nav completeness — checkpoint string mismatch (≈449 fails).**
   `test_text_navigations_complete` compares `string(enumerated)` (plain skeleton,
   e.g. `.elements[1].content{0}`) against `visited::Set{String}` built from
   navigation selections, which are now **canonical (checkpointed)**, e.g.
   `::TextBlock.elements[1].content::String{189}`. Never matches.
   **Fix:** normalise modulo checkpoints — store `strip_reference_types` form in
   `visited` (test/src/editor/TextNavigationTest.jl). Intent-preserving.

2. **`sql_table` example — `length(::Cell)` thrown when a cell is forced (≈460 fails).**
   One broken example cascades through printer/reader/repl/click suites. The
   sql_table projection forces a `Cell(primitive, CellVector(...))` into `length`.
   Pre-existing (noted in c4b4ffd). **Fix:** route the length through the CellVector
   (cf. cb2c900 for the Json analogue).

3. **`TypeReference` checkpoint core bugs (TypeReferenceTest 3 fails: lines 32/44/45).**
   `valid_reference_prefix(document, path)` bails to `EmptyReferencePath()` when
   `applicable(length, document)` is false — but container docs (`JsonArray`)
   support `getindex` without a `length` method, so a valid element checkpoint is
   wrongly truncated. **Fix (production):** make the bounds guard not depend on
   `length` being defined (try index, catch).

4. **Primitive / ConsoleBackend / TableNavigation selection assertions (≈35 fails).**
   Same checkpoint cause: `sel.head` is now a leading `TypeReference`, so
   `sel.head isa FieldReference` etc. fail. **Fix:** `skip_type_checkpoints` in the
   test helpers (`_cursor_at` in PrimitiveTest.jl, console caret asserts, table-nav).

5. **Conversation serialization (7 fails).** tool_use blocks dropped / an extra
   `assistant` message emitted. **Decide:** regression in production vs. test needs
   blessing — determine from the serialization code.

6. **SqlToSyntax test orphans.** `SqlToSyntaxTest.jl:15` iterates a `TextBlock`
   (`out` shape changed); `test_sql_to_syntax_selection` calls undefined
   `test_selection`. **Fix:** update/remove the orphaned test code.

7. **Tabular T10 (10), AssistantMvp (7), Mcp (4), misc.** Investigate per-cluster.

8. **JSON `∅` tree-nav (1).** Genuinely WIP whole-element ∅ navigation. Implement
   or mark broken; smallest item, decide last.

## Process
- Work in the main checkout on `main` (worktree-of-same-branch not possible without
  a new branch, which is disallowed). Commit per cluster.
- After each cluster, re-run the **narrowest** test, not `test_all`.
- Final `test_all()` sweep only once everything else is green.

## Progress
- [x] 1. Text-nav checkpoint normalisation **✅ DONE (re-verified 2026-08-12):** `visited` stores `string(strip_reference_types(path))` — now `package/kernel/test/editor/NavigationTest.jl:68` (file renamed from `TextNavigationTest.jl` and generalised to `NavigationTest.jl`, same fix in place).
- [x] 2. sql_table length (CellTableToTable raw-value thunks) **✅ DONE (re-verified 2026-08-12):** `CellVector(() -> …)` lazy thunks return raw values (no `length(::Cell)`) — file renamed to `package/widget/main/CellTableToWidgetTable.jl:50-60`.
- [x] 3. valid_reference_prefix checkpoint bug (probe getindex, not length) **✅ DONE (re-verified 2026-08-12):** probes `evaluate_reference_step(step, document)` in try/catch instead of `length` — function renamed `get_valid_reference_prefix`, now `package/kernel/main/reference/ReferenceEvaluation.jl:83-107` (and `annotate_reference_types`, same file, :169-189).
- [x] 4. Primitive/ConsoleBackend/TableNav checkpoint asserts **✅ DONE (re-verified 2026-08-12):** `_cursor_at` strips checkpoints before asserting — `package/substrate/test/document/PrimitiveTest.jl:10`; the old `skip_type_checkpoints` helper is gone (a comment at `package/projectured/test/reference/TypeReferenceTest.jl:61` records why: the folded reference form has no interleaved checkpoint steps left to skip), superseded by `strip_reference_types` (`package/kernel/main/reference/ReferenceModule.jl`), exercised at `TypeReferenceTest.jl:30,45,69`.
- [~] 5. Conversation serialization (assistant-turn coalescing in build_messages) **✅ DONE (re-verified 2026-08-12):** consecutive `:assistant` turns coalesced into one logical turn before serialising — `package/workbench/main/WorkbenchAssistant.jl:506-517` (line numbers shifted, same fix in place).
- [x] 6. SqlToSyntax test orphans **✅ DONE (verified):** `test_sql_to_syntax_selection` is now defined and exported (no longer undefined `test_selection`); SqlToSyntaxTest.jl:118,207.
- [~] 7. Tabular / AssistantMvp / Mcp / misc **✅ DONE (verified):** all sub-bullets below are `[x]` and confirmed in tree (e.g. Dragging.jl:198, TypeDispatching.jl:75,80). The `[~]` top-level marker only reflects deferred items 8–14.
  - [x] **ProjectionConfiguring visibility** — ObjectToWidget now outputs a
    `WidgetComposite` wrapping the `GridLayout` (the bar is a real widget with
    `visible`; a layout has none). WidgetComposite renderer now renders embedded
    `LayoutDocument` children, and `GridLayout` is registered in the
    WidgetToGraphics dispatch so the composite's grid re-enters the recursion.
    `_parse_control_edit` made field-aware (keys off `children`) to tolerate the
    composite's leading `elements[…]` step. `test_object_to_widget` +
    `test_projection_configuring` green.
  - [x] **AssistantMvp tool-use round-trip** — root cause was a collection-fold
    regression in `_json_native(::JsonObject)`: it built a `Dict` from a generator
    `for (k,v) in j`, but the `Dict` ctor presizes via `length(j)`, which
    JsonObject no longer forwards → threw → swallowed by try/catch → empty tool
    input → `KeyError("code")` → `is_error=true`. Fixed by iterating `j.entries`.
    Test updated to the correct 2-turn shape (single assistant turn carrying
    `[EvaluatorForm(code="1+1", result≈"2"), TextBlock("Done.")]`). 55/55 green.
  - [x] **Selection-forwarding cluster (click round-trips / cursor re-render)** —
    forward-project the input selection onto each projection's output so a cursor
    re-renders after `set_selection!`:
    - `Focusing.jl`: `projection_print` wires `output.selection` via
      `map_reference_forward` (mirrors Searching).
    - `Searching.jl`: keep raw ref for the fallback; `@invoke` the generic
      `Projection` mapper for projection-introduced positions.
    - `TypeDispatching.jl`: `map_reference_forward/backward` delegate to the inner
      `iomap.projection` (was `nothing`) — transparent dispatcher now maps refs
      end-to-end. **Regression-checked clean**: text-nav 6324/3 (3 pre-existing
      Ctrl+Home seeds), typeins 111/111, json/xml to-syntax + readers, syntax-to-text
      all green (json reader 47/1 = pre-existing line-117 quirk).
    - `FormulaToSyntax.jl` / `CollectionToSyntax.jl`: wire `selection` cells +
      implement/`@invoke` the reference mappers.
    - `SyntaxToText.jl`: collapse-at-cursor strips checkpoints in
      `_resolve_collapsible`; marker hit-test boundary `<=`.
    - `package/odbc/main/ProjecturedOdbc.jl` (file merged into the package module
      file; was `odbc/src/Odbc.jl`) **(finished this session)**: `DatabaseInstanceToDbCatalog`
      is opaque (School B) — backward wraps the catalog-domain ref as `proj(p, …)`
      to live on `inst.selection`, forward unwraps it (stripping the leading
      TypeReference checkpoint `set_selection!` adds), and `projection_print` wires
      `rdbms.selection` forward via `setfn!`. **Verified**: `test_click_roundtrips`
      31/31, `test_collapse_roundtrip` 18/18, `test_mouse_clicks` 29/2 (cleared
      searching/focusing/formula/dbcatalog; `xml_widget`+`dragging` remain — see 9).
  - [x] **Dragging click/nav re-rooting + JsonArray iterate (commit 5aed380).**
    `DraggingProjection`'s reader `else` branch delegated real clicks/keys to the
    inner json chain and returned the inner *content-domain* op unchanged, so
    `set_selection!` on the `DraggingState` couldn't descend into `content` and the
    cursor never re-rendered (broke mouse-click cursor, walk-right termination, and
    repl). Fixed with `prepend_steps_to_op(op, (FieldReference("content"),))` (this
    helper is now named `reroot_operation`, `package/dragging/main/DraggingProjection.jl:204`).
    Also: the `_collect_json_content_strings(::JsonArray)` test helper iterated the
    `JsonArray` directly (no `iterate` after the container migration) → iterate
    `j.elements`. Cleared all 4 dragging fails + the 2 json/json_sorted errors.

## Authoritative `test_all` after the above (commits through 5aed380)
**215601 passed, 19 failed, 2 errored** → after 5aed380: **~13 failed, 0 errored.**
(Down from the 1067/32 baseline.) Remaining failures, **none of which are
tractable rerooting-family bugs** — they were left per an explicit scope decision
to fix only the tractable bugs (dragging/json) and document the rest:

- [ ] 8. **conversation / conversation_widget (5, ReplTest)** — **⏳ OPEN (re-verified 2026-08-12):** `package/conversation/main/ConversationToSyntax.jl:147-155` still has `map_reference_*=nothing` / `read_intent(...)=op` for the 3 conversation→syntax projections. *unimplemented
  feature, not a bug.* The section is still explicitly headed "v1: not wired":
  the 3 conversation→syntax projections stub `map_reference_*  = nothing` and
  the reader passes the operation through unchanged, so a click's syntax-domain
  (`children`-rooted) path is passed through unchanged and FieldErrors on
  `ConversationConversation` (it has `turns`). Real fix = restructure to
  `ChildrenIoMap` + School-A delegation (children↔turns/parts) for both
  ConversationToSyntax **and** ConversationToWidget.
- [ ] 9. **Ctrl+Home seed: filesystem, navigator, conversation_editor (3,
  TextNavigationTest)** — **⏳ OPEN (re-verified 2026-08-12).** The test file
  is now `package/kernel/test/editor/NavigationTest.jl`; the sweep that drives
  it, `package/projectured/test/editor/ExampleSweeps.jl:129-130`, still lists
  exactly `"conversation_editor", "filesystem", "natural", "navigator"` under
  `posnav_seed_broken` with reason `"returned nothing"` — composite documents
  return no selection for `Ctrl+Home`, so the BFS seed is empty. Composite-doc
  navigation feature gap, unchanged.
- [ ] 10. **dbcatalog / dvdrental_catalog walk-right (2, ClickRoundtripTest:271,
  `@test steps>0`)** — **⏳ OPEN (re-verified 2026-08-12).** Test file now
  `package/substrate/test/editor/ClickRoundtripTest.jl`. The position-nav sweep
  (`package/projectured/test/editor/ExampleSweeps.jl:187`) now skips
  `"dbcatalog", "sql_syntax", "sql_table"` outright ("their projections are
  read-only (v1), so they map no references back and Ctrl+Home can't seed a
  selection") rather than tracking a `@test_broken` walk-right count — same
  root cause, now a skip instead of a broken assertion. Needs
  structural/tree-nav semantics for catalog character positions (deep).
- [ ] 11. **xml_widget (2, MouseClick + walk-right)** — **⏳ OPEN (spot-checked 2026-08-12, not re-run).** `xml_widget` no longer
  appears by name in the click-roundtrip skip list
  (`package/projectured/test/editor/ExampleSweeps.jl` around line 365 skips
  `"xml"` but not `"xml_widget"`), so this line item needs a fresh run to
  confirm it is still broken rather than fixed or renamed; not confirmed
  either way here. If still broken: widget-pipeline cursor not
  re-rendered after `set_selection!` (SyntaxToWidget selection-forward gap; deep).
- [x] 12. **table 3×3 Alt+arrow promote (1, TableNavigationTest:192)** — **✅ DONE (verified 2026-08-12):** fixed by commit
  `cbdfdd4b` ("widget-table: Alt+arrow promotes an in-cell cursor to its whole
  cell", 2026-07-18). `package/projectured/test/projection/TableNavigationTest.jl`
  now has a plain `@test nav(KeyDown(:down, ModifierKeys(alt=true)), incell) ==
  ".rows[3][2]"` (around line 197) with no `@test_broken` anywhere in the file —
  `Alt+Down` from an in-cell cursor now promotes to the whole cell and moves.
- [ ] 13. **SqlToSyntax INSERT/UPDATE round-trip (1, SqlToSyntaxTest:113)** —
  **⏳ OPEN (re-verified 2026-08-12):** `SqlSelectItemToSyntaxNode` backward mapping reused for WHERE comparisons persists — `package/sql/main/SqlToSyntax.jl:299-306` hardcodes `::SqlSelectItem`; `test_sql_insert_update_selection` still present (`package/sql/test/projection/SqlToSyntaxTest.jl:74`, exported at :206).
  `backward(forward(.where_clause.condition.expression.left))` returns
  `.where_clause.condition::SqlSelectItem.expression.left`. `SqlSelectItemToSyntaxNode`
  is reused to render the WHERE comparison and its backward hardcodes
  `::SqlSelectItem`. **Ambiguous**: either a stale test that should compare
  modulo checkpoints, or a wrong-type checkpoint (`::SqlSelectItem` on a
  `SqlComparison`) that a test-side strip would *mask*. Needs SqlToSyntax
  expression-reuse analysis before touching.
- [ ] 14. **JSON ∅ tree-nav** and **JsonToSyntax reader line-117 array-insert
  (1)** — **⏳ OPEN, needs re-diagnosis (2026-08-12).** `package/json/main/JsonToSyntax.jl`
  has since been rewritten onto `@projection_template` (per
  [documentation guidance](../../package/kernel/doc/macros.md) to prefer that
  macro); the old reader's line-117 array-insert quirk could not be re-located
  by line number under the new implementation. `"json"` does not appear in the
  current `tree_broken` registry
  (`package/projectured/test/editor/ExampleSweeps.jl:232-243`), so the ∅
  tree-nav half of this item may already be fixed — needs a real test run to
  confirm, not a line citation.
