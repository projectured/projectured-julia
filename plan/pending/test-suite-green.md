# Get the complete test suite green

`test_all()` on `main@8823a0a` reports **210158 passed, 1067 failed, 32 errored**.
The failures collapse to a handful of root causes accumulated across the
keyword-constructor / ProjectionTemplate / TypeReference-checkpoint migration
series. Several were documented as "pre-existing" in recent commit messages.

## Root causes (by leverage)

1. **Text-nav completeness — checkpoint string mismatch (≈449 fails).**
   `test_text_navigations_complete` compares `string(enumerated)` (plain skeleton,
   e.g. `.elements[1].content{0}`) against `visited::Set{String}` built from
   navigation selections, which are now **canonical (checkpointed)**, e.g.
   `::TextText.elements[1].content::String{189}`. Never matches.
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

6. **SqlToSyntax test orphans.** `SqlToSyntaxTest.jl:15` iterates a `TextText`
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
- [x] 1. Text-nav checkpoint normalisation
- [x] 2. sql_table length (CellTableToTable raw-value thunks)
- [x] 3. valid_reference_prefix checkpoint bug (probe getindex, not length)
- [x] 4. Primitive/ConsoleBackend/TableNav checkpoint asserts
- [~] 5. Conversation serialization (assistant-turn coalescing in build_messages)
- [x] 6. SqlToSyntax test orphans
- [~] 7. Tabular / AssistantMvp / Mcp / misc
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
    `[EvaluatorForm(code="1+1", result≈"2"), TextText("Done.")]`). 55/55 green.
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
    - `odbc/src/Odbc.jl` **(finished this session)**: `DatabaseInstanceToDbCatalog`
      is opaque (School B) — backward wraps the catalog-domain ref as `proj(p, …)`
      to live on `inst.selection`, forward unwraps it (stripping the leading
      TypeReference checkpoint `set_selection!` adds), and `projection_print` wires
      `rdbms.selection` forward via `setfn!`. **Verified**: `test_click_roundtrips`
      31/31, `test_collapse_roundtrip` 18/18, `test_mouse_clicks` 29/2 (cleared
      searching/focusing/formula/dbcatalog; `xml_widget`+`dragging` remain — see 9).
- [ ] 8. JSON ∅ tree-nav
- [ ] 9. **Pre-existing, not yet fixed** (surfaced, not regressions):
  - `test_mouse_clicks`: `xml_widget` + `dragging` — widget-pipeline / NestingProjection
    cursor not re-rendered after `set_selection!` (same family, SyntaxToWidget /
    DraggingProjection don't forward selection).
  - `test_text_navigations`: `filesystem`, `navigator`, `conversation_editor` —
    Ctrl+Home returns no selection (seed failure → `state_count==0`).
  - `test_table_navigation` (1, WidgetToGraphics.jl); SqlToSyntax `sql_table` printer
    length-on-CellVector; JsonToSyntax reader line-117 array-insert.
