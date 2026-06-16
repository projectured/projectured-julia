# Projection documentation overhaul + uncovered code fixes

Goal: make the projection documentation correct, consistent, and useful for
implementors (especially AI agents). A close read of all projection source
(primitive / generic / higher-order / compound) against the guides surfaced
stale docs **and** several genuine code bugs. This plan tracks both.

Decisions below were settled in a Q&A review on 2026-06-16.

## Code fixes (do these first — docs must describe the code as it will be)

All five code fixes are **done and verified** (full sweep: 6422 pass; the only
5 failures pre-exist on the clean base — `object_to_widget`, `filesystem`,
`navigator`, `conversation_widget`, `conversation_editor`, all "Ctrl+Home
returned no selection").

- [x] **B4 — `projection_printer_recurse` helper.** Add
  `projection_printer_recurse(recursion, input, ctx) =
  projection_print(recursion, recursion, input, ctx)` (in `api/Projection.jl`
  or `common/Projection.jl`). Migrate every node printer (~20: the `*ToSyntax`
  nodes, generic Copying/Sorting/Reversing, etc.) and the `child_iomaps`
  recursion sites to call it, so the `recursion, recursion` doubling lives in
  exactly one place. Name must contain both "printer" and "recurse".
- [x] **C6 — Element vs Position (bug).** Recursing into the i-th element must
  pass `ElementReference(i)`, not the zero-width `PositionReference(i)`. Fix
  `child_context` calls in Copying.jl (57, 107), Sorting.jl (54, 70, 84),
  Reversing.jl (34). Also fix the coupled `_map_ref` output in Copying.jl:204
  (emits `PositionReference(j)` for CellVector children on the selection-mapping
  axis). Verify round-trip with `test_json` / `test_syntax`.
- [x] **E9 — default reader re-targets all reference-carrying ops (bug).**
  Generalize the default `projection_read(::Projection, iomap, operation)` in
  common/Projection.jl: besides `ReplaceSelectionOperation`, re-target
  `StringReplaceRangeOperation` / `NumberReplaceRangeOperation` (and any future
  reference-carrying op) via `map_reference_backward`. This makes editing work
  through Sorting/Reversing/Copying and any generic projection by default.
  Verify with a sort-then-edit test.
- [x] **G12 — union dispatch keys.** Loosen `TypeDispatchingProjection` from
  `Pair{DataType,Any}` to `Pair{Type,Any}` so `Union{A,B} => proj` constructs
  (`input isa T` already handles unions). Document union keys as supported.
- [x] **G14 — CopyingProjection must be domain-independent (bug).** *Resolved
  via Option 3: a new `ScreenToScreen` primitive projection.* It owns all
  screen-domain structure — copies the `ScreenDocument` shell, copies each
  `WindowDocument`'s metadata verbatim and recurses its `content` (seeding
  width/height as layout extent), and on the reader side routes an
  `EventEnvelope` to the matching window by `window_id`, prefixing the returned
  op with `windows[i].content`. `WindowManagerProjection` stays a thin
  op-interceptor wrapping it (`inner = ScreenToScreen()`). CopyingProjection now
  has **no** `projection_read` method and no `ScreenDocument`/`WindowDocument`/
  `EventEnvelope` imports — fully generic again. Examples + TooltipTest updated
  to `ScreenToScreen`; window-content dispatch targets changed `windows{i}` →
  `windows[i]` (consistent with the C6 ElementReference convention).
  `test_tooltip` (open/close/resize) and click-roundtrips pass.

## Documentation fixes

- [x] **A1/A2 — reader is the 4-arg `Change` interface, taught up front.**
  Rewrite the reader description in projection-system.md, operations.md, and
  selection-deep-dive.md §6 to use `projection_read(p, recursion, change::Change,
  iomap) -> Change` and explain `Change(gesture, operation)` threading. The
  3-arg `projection_read(p, iomap, event_or_op)` form is **obsolete** — present
  it (if at all) only as a transitional shim being removed.
- [x] **A3 — gesture rationale.** Use SyntaxToText's mouse hit-test as the
  worked example of why `gesture` rides along unchanged (the reader needs the
  raw click coordinates even though selection is what comes back).
- [x] **B4 docs.** Write the compound-printer recipe against
  `projection_printer_recurse`.
- [x] **B5 — printer signature sweep.** Fix all 4-arg printer signatures in the
  guides (the deep-dive §5/§8 samples have wrong arity and swapped args). Sweep
  every guide for "reference" used in the 4th printer-arg slot → it is a
  `PrinterContext` (`ctx`) that *carries* the reference path plus layout extent
  and properties. Note the historical promotion from raw `ReferencePath`.
- [x] **D7 — reference construction.** Make `@reference` the canonical way to
  build references; `ReferencePath(steps…)` the secondary programmatic form;
  remove hand-nested `ConcreteReferencePath`/`EmptyReferencePath` examples
  (keep at most a one-line "under the hood it's an immutable linked list").
- [x] **D8 — whole-element selection.** Document the `∅` `@reference_case`
  pattern and the convention that an empty path selects the whole element
  (no sub-position). Not in-flux.
- [x] **F10 — one canonical inventory.** Make the projection-system.md category
  table the single exhaustive list (all 10 higher-order incl. WindowManager,
  TooltipDecorator, ProjectionConfiguring; all 9 generic incl. Filtering,
  Searching, ObjectToWidget). Per-category guides match it exactly.
- [x] **F11 — define "generic".** Generic = **input-domain-independent**
  (operates on any document by structure, not by type). Most also preserve the
  domain; `ObjectToWidget` is input-independent but produces widgets — describe
  it that way, not as an "exception" to the category.
- [x] **G13 — NestingProjection precedence.** Document that the stored
  `recursion` overrides the inherited one (falling back to inherited only when
  none is stored), and that this is what lets `ApplyAtProjection` preserve the
  target subtree's contents.

## Verification

After code fixes, run the narrowest covering tests (`test_json`, `test_syntax`,
`test_json_to_syntax`, sort/edit cases) rather than `test_all`.
