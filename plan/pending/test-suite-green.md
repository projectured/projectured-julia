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
- [ ] 1. Text-nav checkpoint normalisation
- [ ] 2. sql_table length
- [ ] 3. valid_reference_prefix checkpoint bug
- [ ] 4. Primitive/ConsoleBackend/TableNav checkpoint asserts
- [ ] 5. Conversation serialization
- [ ] 6. SqlToSyntax test orphans
- [ ] 7. Tabular / AssistantMvp / Mcp / misc
- [ ] 8. JSON ∅ tree-nav
