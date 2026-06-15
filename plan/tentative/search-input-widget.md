# ProjectionConfiguringProjection — later stages

Stage 1 (core `ProjectionConfiguringProjection` + `ObjectToWidget` +
`ReplaceReferencedValue` for `TextHighlighting`/`TextFiltering`) is done —
see [plan/done/search-input-widget.md](../done/search-input-widget.md).

## Stage 2 — make the generic projections cell-reactive (chosen path)

Bring `FilteringProjection` / `SearchingProjection` into the same mechanism by
refactoring them to hold their *editable* parameters in `Cell`s read inside
reactive thunks (mirroring `TextFiltering`):

- `SearchingProjection`: replace `pattern::Regex` with `pattern_source::Cell{String}`
  (+ `case_insensitive::Cell{Bool}`); derive the `Regex` and the default
  `field_match` reactively. The arbitrary-`field_match::Function` constructor
  stays as a non-editable escape hatch.
- `FilteringProjection`: add an editable common-case form (a pattern string
  `Cell` + optional field-name selector) that builds the predicate internally.
  Keep the raw `predicate::Function` constructor for programmatic use —
  `ObjectToWidget` simply renders no control for it.

Keep the existing positional constructors working (wrap raw args in `Cell`) so
current examples/tests are unaffected. Then point
`ProjectionConfiguringProjection` at them — no new wiring, only which `Cell`
fields `ObjectToWidget` surfaces. After this all four projections share one
editable-pattern convention.

## Stage 3 (optional) — floating overlay instead of stacked

Swap the `WidgetSplitPane` for a `WidgetTooltip` / window / `AnchoredLayout`
([anchored-layout.md](../pending/anchored-layout.md)) positioned over the
document, toggled by a Ctrl+F gesture handled the way `WindowManager` handles
`OpenWindowOperation`/`CloseWindowOperation`. `orientation`/placement becomes a
`:floating` mode on the same wrapper.

## Resolved decisions

- **Promote scalar params to `Cell`s** (`invert`, case-insensitive flags) so
  `ObjectToWidget` can edit them as checkboxes. Done in Stage 1 (Phase 1a) for
  the text projections; Stage 2 for the generic ones.
- **Reader emits a reference-targeted operation** (`ReplaceReferencedValue`,
  carrying the projection as its own root + a `FieldReference` + the parsed
  value), evaluated by the editor — never a raw `Cell`, never a direct mutate.
  Parameters can stay in the projection struct because the operation carries its
  own resolution root rather than resolving against `editor.document`.
- **Reactivity refactor** (not re-`projection_print`) for the generic
  projections.
- **Regex** edited via its source string + flag checkboxes; **`Function`**
  parameters are non-editable escape hatches `ObjectToWidget` skips.

## Open questions

- Parameters stay in the projection struct (`ReplaceReferencedValue` carries its
  own root). Undo replay works since the operation is self-contained. Only if the
  controls must participate in document-rooted **selection** would the parameters
  need to become a first-class document in the tree — defer unless needed.
- Field labels: derive from `fieldname` (simple) or allow a per-projection
  display-name map (nicer UX). Start with `fieldname`.
