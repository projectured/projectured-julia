# ProjectionConfiguringProjection — editable controls for a projection's parameters

A higher-order `ProjectionConfiguringProjection` wraps an inner ("parameter")
projection: it applies the inner projection to the input *and* extends the
output with a control document that edits the inner projection's parameters
live. The control part is produced by a simplified, reusable `ObjectToWidget`
projection. First version stacks control-above-document.

This generalises the per-projection "search box" idea: instead of hand-building
a widget for each searching/filtering/highlighting projection, one wrapper
configures *any* projection whose parameters live in reactive `Cell` fields.

## Implementation status (Stage 1)

Implemented and unit-tested:
- **Phase 1a** — `TextHighlighting`/`TextFiltering` now hold a polymorphic
  `pattern::Cell` (String source | Regex | nothing) + `case_insensitive::Cell`;
  `TextFiltering.invert` is a `Cell`. (Kept the field name `pattern` rather than
  renaming to `pattern_source` to preserve the existing `Cell{Regex}` reactivity
  tests.) Regex derived reactively; empty source = pass-through.
- **Phase 1b** — `ReplaceReferencedValue(document, reference, value)` operation;
  `ObjectToWidget` reflects renderable scalar `Cell` fields into
  `WidgetText`/`WidgetCheckbox` rows and redirects a control's edit (matched by
  widget identity) onto the object's field.
- **Phase 1c** — `ProjectionConfiguringProjection` (stacked vertical
  `WidgetSplitPane`; reader routes control edits / `Ctrl+F`+`Escape` show-hide /
  document edits).
- **Phase 1d** — `run_example(...; text_highlighting=true | text_filtering=true)`
  via `make_text_configuring_projection` (defaults the pattern to `"dolor"` so the
  highlight is visible out of the box). Full print pipeline verified to a
  `GraphicsCanvas` (control bar + highlighted document) with a stub measure; live
  font rasterisation needs the SDL window, like all widget examples.
  - Fixed an **empty-screen** bug: `WidgetSplitPane` only renders
    `WidgetDocument` slots, so PCP's raw `TextText` document slot was dropped.
    PCP now wraps a non-widget projected document in a `WidgetScrollPane` (the
    assistant-input pattern).
- **Widget interactivity** —
  - `WidgetCheckbox` click emits `ReplaceReferencedValue(self, content, !value)`,
    closing the boolean loop.
  - `WidgetText` is now **editable** when its `content` is a `Document`: it
    recurses the content through the Text domain (TextToGraphics), so all caret
    navigation and text editing originate there and the widget only re-roots the
    operations by prepending `content` (the `WidgetScrollPane` pattern). A plain
    (string) content still stringifies as before. Standalone demo:
    `run_example(widget_text_example)` (`example/src/document/Widget.jl`).

- **Control loop fixed (boolean parameters).** The blocker was that
  `WidgetComposite` only routed `MouseScroll` — clicks/keys never reached the
  control bar. Gave `WidgetCompositeToGraphicsCanvas` the same routing as
  `WidgetSplitPane` (hit-test `MousePress`, selection/fallback for coordless
  events, re-root with `elements[i]`). End-to-end verified: clicking a
  control-bar checkbox routes renderer → split pane → composite rows → checkbox
  → `ReplaceReferencedValue` → PCP redirect → flips the inner projection's
  `case_insensitive` / `invert` cell live. Regression: readers / repls /
  selections sweeps all clean.

Deferred: **editable pattern (text) control.** Boolean controls work because a
click is a stateless identity op (`ReplaceReferencedValue`). A *text* control
needs a persistent caret, but the control bar has no input-document backing for
that cursor state (it is pure projection output), and key events route by the
input-document selection — which the control bar lacks. Making the pattern field
editable therefore needs either a local focus model for the control bar (a
"focused control" + an `Edit…`-against-a-carried-root operation) or promoting the
parameters to first-class documents in the input tree. Until then, set the
pattern programmatically (`TextHighlighting("dolor")`) and toggle flags by click.
v1 reference mapping through the configuring split pane is `nothing` (no cursor
mapping through the control bar).

## Stage 1 scope

**Stage 1 targets only `TextHighlighting` and `TextFiltering`** — the two
projections that already hold their pattern in a reactive `Cell` and build their
output from cell-reading thunks, so configuring them is live for free. Stage 1
delivers `ReplaceReferencedValue` + `ObjectToWidget` + `ProjectionConfiguringProjection`
(stacked, with a show/hide-controls toggle in its reader), wired to these two
only, plus `text_filtering` / `text_highlighting` flags on `run_example` to demo
them on any example.

`FilteringProjection` / `SearchingProjection` (which read parameters eagerly and
hold no cells) and the floating-overlay presentation are **explicitly out of
Stage 1** — see Later stages.

## Key insight

A projection's parameters already live in its struct fields. The reactive ones
are `Cell`s:

| Projection | `Cell` parameter fields | Non-cell fields |
|---|---|---|
| `TextHighlighting` ([TextHighlighting.jl](../../program/src/projection/primitive/TextHighlighting.jl)) | `pattern::Cell` | `color` |
| `TextFiltering` ([TextFiltering.jl](../../program/src/projection/primitive/TextFiltering.jl)) | `pattern::Cell` | `invert::Bool` |
| `FilteringProjection` ([Filtering.jl](../../program/src/projection/generic/Filtering.jl)) | — | `predicate::Function` |
| `SearchingProjection` ([Searching.jl](../../program/src/projection/generic/Searching.jl)) | — | `pattern::Regex`, `field_match::Function` |

So the "data structure" the controlling widget edits *is the inner projection
itself*. `ObjectToWidget` reflects over the projection's `Cell` fields and emits
one control per field; the reader writes edits straight back into those cells.
Because the inner projection's printer reads its `Cell`s inside reactive thunks
(true for `TextHighlighting`/`TextFiltering`), editing a control re-projects the
document live with **no re-`projection_print`**.

## Caveat: inner output must be cell-reactive

Live update works only when the inner projection builds its output from thunks
that read its parameter `Cell`s.
- `TextHighlighting` / `TextFiltering` — already thunk-reactive. Work for free.
- `FilteringProjection` / `SearchingProjection` — read parameters eagerly at
  print time and hold no `Cell`s. **Chosen path: the reactivity refactor**
  (Stage 2), not re-running `projection_print` — move parameters into `Cell`s
  and read them inside reactive thunks, mirroring `TextFiltering`. Out of
  Stage 1.

## What is (and isn't) editable

`ObjectToWidget` renders **only scalar `Cell` fields it knows how to display**;
everything else is skipped (no control, no operation). This decides how each
parameter kind is handled:

- **Regex — edit the source, not the object.** A compiled `Regex` is opaque, so
  the canonical editable parameter is a `Cell{String}` (the pattern source) plus
  optional `Cell{Bool}` flag cells (case-insensitive, multiline). The `Regex` is
  *derived* in a reactive thunk: `Regex(source, options)`. `TextFiltering` /
  `TextHighlighting` therefore shift from `pattern::Cell{Regex}` to
  `pattern_source::Cell{String}` (+ flag cells); the regex becomes internal.
  Bonus: case-insensitivity becomes a checkbox instead of being baked in.
- **Function (predicate) — not editable; skipped.** A raw `Function` can't be a
  control, so `ObjectToWidget` shows nothing for it. To make
  `FilteringProjection` configurable, the Stage-2 refactor reframes its
  *editable surface* to the common case both generic projections already use: a
  pattern string `Cell` (+ optional field-name selector) from which the
  projection builds its predicate internally. The arbitrary-`Function`
  constructor stays as a non-editable power-user escape hatch.
- **Bool / Number / String** — direct controls (`WidgetCheckbox` / `WidgetText`).
- **StyleColor and other rich types** — skipped in v1.

Rule of thumb: a projection becomes configurable by exposing its parameters as
renderable scalar `Cell`s; opaque forms (`Function`, compiled `Regex`) remain as
escape hatches `ObjectToWidget` quietly ignores.

## Existing infrastructure reused

- **Controls** — `WidgetText`, `WidgetCheckbox`, `WidgetLabel`
  ([Widget.jl](../../program/src/document/Widget.jl)), assembled as in
  [ConversationToWidget.jl](../../program/src/projection/primitive/ConversationToWidget.jl).
- **Stacking control above document** — vertical `WidgetSplitPane`, exactly as
  `WorkbenchAssistantToWidgetSplitPane`
  ([WorkbenchToWidget.jl:275](../../program/src/projection/primitive/WorkbenchToWidget.jl#L275))
  stacks an input pane above a content pane.
- **Higher-order wrapper + reader interception** — `WindowManagerProjection`
  ([WindowManager.jl](../../program/src/projection/higherorder/WindowManager.jl))
  is the template: printer passes through to an inner projection, reader
  intercepts the events it owns and delegates the rest.

# Stage 1 — TextHighlighting / TextFiltering (stacked)

## Phase 1a — Regex-source shift on the two text projections

Make their pattern editable as a string before reflecting over it. Shift
`TextHighlighting` / `TextFiltering` from `pattern::Cell{Regex}` to
`pattern_source::Cell{String}` (+ optional `case_insensitive::Cell{Bool}`),
deriving the `Regex` inside the existing reactive thunks via
`Regex(source, options)`. `TextFiltering.invert::Bool` → `invert::Cell{Bool}` so
it becomes a checkbox. Keep the current positional/`Regex`/`String` constructors
working (wrap into the new cells) so existing examples and tests are unaffected.

Verify with `test_printer(textfiltering_example)` / `test_printer(texthighlighting_example)`
before touching the widget layer.

## Phase 1b — simplified ObjectToWidget

`program/src/projection/generic/ObjectToWidget.jl` (new module).

A projection from an arbitrary object to a `WidgetComposite` form, driven by
reflection over the object's `Cell` fields.

- `struct ObjectToWidget <: Projection; fields; end`
  - `fields=nothing` ⇒ auto-detect: every `Cell`-typed field whose current
    value is editable (`String`, `Regex`, `Bool`, `Number`).
  - `fields=[:pattern, :invert]` ⇒ explicit whitelist/order.
- `projection_print(p, recursion, obj, ctx)`:
  - For each **renderable scalar `Cell`** field (skip `Function` / `StyleColor`
    / other rich types — see "What is (and isn't) editable"), read the value and
    choose a control:
    - `String` / `Number` → `WidgetText` (content = `string(value)`),
    - `Bool` → `WidgetCheckbox`.
  - Emit a row `WidgetComposite[ WidgetLabel(fieldname), control ]`, stack rows
    vertically into a `WidgetComposite` (reuse the `_stack_vertical!` /
    `_compose` recipe from `ConversationToWidget`).
  - IoMap records, per control, the target field `Cell` and a parser
    (`String→Int`, identity for `Bool`/`String`).
- `projection_read(p, iomap, op)` — **emits operations, never mutates directly**:
  - Locate the control the edit targets, parse the new value to the field's
    type, and return
    `ReplaceReferencedValue(p.object, FieldReference(name), parsed_value)`
    (new operation; see below). Invalid input (e.g. unparseable number) ⇒
    return `nothing`.
- `map_reference_forward/backward` ⇒ `nothing` in v1 (control subtree does not
  map into the source document), as `ConversationToWidget` does.

### New operation: ReplaceReferencedValue

A reference-targeted setter that carries **its own root** — so it works on a
projection's parameter fields without those parameters living in
`editor.document`. It is `ReplaceDocumentOperation` generalised: an explicit
root object + a field reference + a scalar value, reusing the same
terminal-slot-write machinery.

`program/src/common/Operation.jl` (alongside the other generic operations):

```julia
struct ReplaceReferencedValue <: Operation
    document::Any            # root the reference resolves against (here: the projection)
    reference::ReferencePath # e.g. FieldReference("pattern_source")
    value::Any               # already-parsed new value
end

function evaluate_operation(editor, op::ReplaceReferencedValue)
    parent_path, terminal = _split_terminal_step(op.reference)
    parent = parent_path isa EmptyReferencePath ? op.document :
             evaluate_reference(op.document, parent_path)
    _write_value_slot!(parent, terminal, op.value)   # FieldReference → set the Cell field
end
```

`_write_value_slot!(parent, ::FieldReference, value)` writes into the named
`Cell` field — the scalar twin of `_write_document_slot!`
([Operation.jl:125](../../program/src/common/Operation.jl#L125)). Because that
`Cell` feeds the inner projection's reactive thunks, the document re-projects on
the next frame with **no re-`projection_print`**.

`ObjectToWidget` holds the projected object as `iomap.object` and records, per
control, the `FieldReference` whose `Cell` it edits.

### Test
`test_printer` / `test_reader` on a tiny example object with a `pattern::Cell`
and a `Bool` cell. Per CLAUDE.md, the narrowest test that covers the change.

## Phase 1c — ProjectionConfiguringProjection (stacked)

`program/src/projection/higherorder/ProjectionConfiguring.jl` (new module).

- `struct ProjectionConfiguringProjection <: Projection; inner; control; orientation; end`
  - `control` defaults to `ObjectToWidget()`; `orientation` defaults to
    `:vertical` (control on top).
- `projection_print(p, recursion, input, ctx)`:
  - `inner_iomap = projection_print(p.inner, recursion, input, ctx)`.
  - `control_iomap = projection_print(p.control, p.control, p.inner, ctx)`
    — i.e. project the **inner projection object** into a control widget.
  - Combine: `WidgetSplitPane(p.orientation, Any[ control_iomap.output,
    inner_iomap.output ])` (constraints copied from
    `WorkbenchAssistantToWidgetSplitPane`).
  - Return an iomap holding both child iomaps + the combined output.
- `projection_read(p, recursion, change, iomap)`:
  - **Show/hide controls** — intercept a toggle gesture (e.g. `Ctrl+F`, plus a
    distinct hide on `Escape`) and return `ShowWidgetOperation` /
    `HideWidgetOperation` ([Widget.jl:741](../../program/src/document/Widget.jl#L741))
    on the control composite, flipping its `visible` cell. Lets the control bar
    stay hidden until summoned and dismissed without leaving the document. The
    wrapper stores the control widget on its iomap so the reader can name it.
  - If the gesture targets the control subtree ⇒
    `projection_read(p.control, iomap.control_iomap, …)` (writes parameter
    cells; consumes the event).
  - Else ⇒ `projection_read(p.inner, recursion, change, iomap.inner_iomap)`
    (document edits pass through).
  - Routing model = `WindowManagerProjection`'s reader (intercept the events it
    owns, delegate the rest).
- `map_reference_forward/backward` ⇒ delegate to `inner_iomap` for the document
  slot; control slot maps to `nothing` in v1.

### Example + test
- `example/src/projection/ProjectionConfiguring.jl`: wrap the existing
  `TextHighlighting(r"dolor")` and `TextFiltering` examples. Editing the
  pattern control re-highlights / re-filters live.
- Verify with `test_printer` / `test_reader` on that one example, then
  `test_syntax_to_text()` if the text pipeline is touched.

## Phase 1d — run_example integration

Add two boolean flags to `run_example`
([Examples.jl:103](../../example/src/Examples.jl#L103)), following the existing
`caching` / `scrolling` / `tooltip` / `introspection` wrapping pattern:

- `text_filtering=false` — when set, splice a `TextFiltering` (wrapped in
  `ProjectionConfiguringProjection`) into the example's projection pipeline.
- `text_highlighting=false` — likewise with `TextHighlighting`.

When either is on, the example's projection is replaced by
`ProjectionConfiguringProjection(inner=<the text projection>, ...)` over the
example's existing projection, so the configurable control bar appears stacked
above the rendered document. Both may be on together (compose the wrappers).
Default off keeps every current `run_example` call unchanged.

This makes Stage 1 demoable on any text-producing example, e.g.
`run_example(json_example; text_highlighting=true)`, with `Ctrl+F` to summon the
control bar and live edits to the pattern.

# Later stages (out of Stage 1)

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
