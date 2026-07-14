# Enable clipboard, dragging, tooltip, text filtering, searching & highlighting in the workbench example

## Goal

The standalone `run_example` flags already exercise these projections one at a
time (`tooltip=true`, `text_filtering=true`, `text_highlighting=true`,
`clipboard_example`, `dragging_example`). The workbench example
(`make_workbench_document_example` / `make_workbench_projection_example`) is the
flagship multi-panel demo but currently uses **none** of them. This plan wires
all six into the workbench so they are usable together in the IDE-style layout.

The central design question this plan answers: **where does each projection
belong?** They split cleanly into three placement classes, because each
projection attaches to the pipeline through one of three different mechanisms.

## Configuration UI: `ProjectionConfiguringProjection`

**Any projection that needs user configuration is added by wrapping it in
`ProjectionConfiguringProjection`** (`higherorder/ProjectionConfiguring.jl`)
rather than by hand-wiring a custom control panel. Its printer runs the inner
projection, projects the inner projection *object itself* through `ObjectToWidget`
into an editable control bar, and stacks the two in a `WidgetSplitPane` (control
above output). Because the control edits the **same parameter `Cell`s the inner
projection reads in its reactive thunks**, editing re-projects live. The reader
already handles it: `Ctrl+F` toggles the bar, `Escape` hides it, control edits
become `ReplaceReferencedValue` on the parameter cell, document edits delegate to
the inner reader.

This applies to our three *parameterised* projections — **`TextFiltering`,
`TextHighlighting`, and `SearchingProjection`** (pattern, case-insensitive,
invert). It does **not** apply to clipboard / dragging / tooltip: those are
gesture-driven and carry no user-tunable parameters (clipboard's display toggles
are keyboard ops, not config fields).

Key consequence for placement: `ProjectionConfiguringProjection` **emits widgets**
(a `WidgetSplitPane`), so it cannot sit raw in the middle of a `Text → Text →
Graphics` chain. It must be followed by a widget+text→graphics renderer — exactly
the `SequentialProjection(ProjectionConfiguringProjection(inner=…), renderer)`
shape `make_text_configuring_projection` already uses
(`example/src/projection/Wrapper.jl:43`). One more consequence:
`ObjectToWidget` edits parameter **`Cell`s**, so a configured projection's tunable
parameters must be `Cell`-valued fields — see the `SearchingProjection` gap below.

## The three placement classes (the design answer)

ProjecturEd has exactly three ways a projection enters a running pipeline, and
each of our six features uses one of them:

### A. Configured `Text → Text` stages inside a per-document-type content chain

These are domain-preserving `Text → Text` projections that render a given
document type. In the workbench the chain lives in the `combined_w2g`
`TypeDispatchingProjection` of `make_workbench_projection_example`
(`example/src/projection/Workbench.jl`), e.g. the JSON entry today is
`Json → Syntax → Text → TextToGraphics`.

- **`TextFiltering`** (`primitive/TextFiltering.jl`) — drops non-matching lines.
- **`TextHighlighting`** (`primitive/TextHighlighting.jl`) — paints a swatch
  behind matches, keeping every line.

Both are **parameterised, so they are added via `ProjectionConfiguringProjection`**
(see above), not as a bare pipeline step. A configured JSON-with-highlighting
entry becomes:

```julia
JsonDocument => SequentialProjection(
    ProjectionConfiguringProjection(inner = SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextHighlighting(),          # idle until its pattern cell is set
    )),
    renderer,                         # widget+text → graphics (combined_w2g shape)
)
```

The `inner` runs `… → TextBlock`; the configuring projection stacks the control
bar above it and emits a `WidgetSplitPane`; the trailing `renderer` (a
`RecursiveProjection(TypeDispatchingProjection(w2g.dispatch + TextBlock⇒TextToGraphics))`,
i.e. the same renderer shape `combined_w2g` already is) turns it into graphics.
A `nothing`/empty pattern is a pass-through, so a configured stage can sit
permanently in the chain and stay idle until the user types in its control bar.

> These go in the **per-document-type pipeline** because they are inherently
> about text rendering and only make sense for text-bearing content (console,
> editors whose tail is a `TextBlock`). The inner text projection must be
> downstream of `SyntaxToText`; the configuring wrapper + renderer replace the
> bare `TextToGraphics` tail.

### B. Wrapper documents dispatched in the same type table

These features are driven by a **marker document** that wraps a `content`/`child`
sub-tree; a projection dispatches on the wrapper type and is otherwise
transparent. Enabling them is two coordinated edits:

1. **Wrap** the target document in `make_workbench_document_example` (e.g. an
   editor's content, a collection, or a whole page's element list).
2. **Add a dispatch entry** for the wrapper type in the `combined_w2g`
   `TypeDispatchingProjection` so the wrapper is projected by its decorator.

- **Clipboard** — `ClipboardSlice` / `ClipboardCollection`
  (`document/Clipboard.jl`) wrap `content`; `ClipboardSliceToAnyProjection` /
  `ClipboardCollectionToAnyProjection` (`primitive/ClipboardToAny.jl`) dispatch
  on them. Ctrl+C/X/V/N + Ctrl+/ (slice display) / Ctrl+* (collection display).
  Generic over any content — wrap the structured editors (JSON/XML) where
  copying sub-documents is meaningful.
- **Dragging** — `DraggingState` (`document/Dragging.jl`) wraps `content`;
  `DraggingProjection` (`higherorder/Dragging.jl`) dispatches on it and emits a
  `MoveRangeOperation` to reorder a `CellVector`. Wrap a node with reorderable
  element lists (a JSON array, XML element children, or the page's panel list).

> These go **per-document, in the dispatch table**, because the behavior is
> attached to a specific sub-tree by wrapping it; the decorator is transparent
> everywhere else. They are still "generic" (work on any content), but their
> placement is local to whichever document the user wraps.

### C. The screen / workbench-general layer

These two are not local to one document — they cross panel boundaries or escape
to the screen root.

- **Tooltip** — `TooltipSource` (`document/Tooltip.jl`) wraps `child`;
  `TooltipDecoratorProjection` (`higherorder/TooltipDecorator.jl`) dispatches on
  it but emits `OpenWindowOperation` / `CloseWindowOperation` that bubble all the
  way up to **`WindowManagerProjection` at the `ScreenDocument` root**. So a
  tooltip is a *screen-level* concern: it needs the screen pipeline
  (`run_example` already wraps the workbench in a `ScreenDocument` →
  `WindowManagerProjection(inner=ScreenToScreen())`). Today
  `tooltip=true && workbench=true` is an explicit error in `run_example`
  (`Examples.jl:220`); lifting that restriction is part of this work.
  - Placement: wrap a chosen workbench sub-node (e.g. the descriptor target, or
    each editor) in a `TooltipSource`, and add a `TooltipSource` dispatch entry
    in `combined_w2g`. The decorator op bubbling is already handled by the
    existing screen pipeline `run_example` builds.

- **Searching** — `SearchingProjection` (`generic/Searching.jl`) is a deep,
  document-wide walk producing a flat `CellVector` of matches. This is the
  **`WorkbenchSearcher` panel's** job (today the panel is empty —
  `WorkbenchSearcherToWidgetScrollPane` renders `nothing`). It is parameterised
  (the search pattern), so its UI is **also a `ProjectionConfiguringProjection`**:
  the control bar is the query input, and the inner `SearchingProjection`'s
  result list renders below. Make the `WorkbenchSearcher` panel project to
  `ProjectionConfiguringProjection(inner = SearchingProjection(...))` over the
  search target.

> Searching is the **general control point**: its control bar is where the user
> sets the pattern. If you want that pattern to *also* drive the editors'
> `TextHighlighting`/`TextFiltering` (type once, highlight everywhere), share the
> *same* underlying `pattern::Cell` object across the searcher's
> `SearchingProjection` and the editors' configured projections — the control
> edits the cell, every projection reading it re-projects. That cross-panel
> sharing is optional; without it each configured projection just carries its own
> independent control bar.

## Summary table

| Feature | Mechanism | Config UI | Where it goes | Files touched |
|---|---|---|---|---|
| Text filtering | A: configured text stage | `ProjectionConfiguringProjection` | text chains in `combined_w2g` | `example/src/projection/Workbench.jl` |
| Text highlighting | A: configured text stage | `ProjectionConfiguringProjection` | text chains in `combined_w2g` | `example/src/projection/Workbench.jl` |
| Clipboard | B: wrapper + dispatch | none (gestures) | wrap structured editors; dispatch entry | `example/src/document/Workbench.jl`, `example/src/projection/Workbench.jl` |
| Dragging | B: wrapper + dispatch | none (gestures) | wrap a list-bearing node; dispatch entry | same two example files |
| Tooltip | C: screen-level | none (gestures) | wrap sub-node; dispatch entry; allow tooltip+workbench | both example files + `example/src/Examples.jl` |
| Searching | C: workbench-general | `ProjectionConfiguringProjection` | `WorkbenchSearcher` projects to `ProjectionConfiguringProjection(SearchingProjection)` | `document/Workbench.jl`, `WorkbenchToWidget.jl`, example files |

## Shared infrastructure to build first

> **⏳ OPEN (verified 2026-06-23):** Neither infra step is done. `SearchingProjection.pattern`
> is still a plain `Regex` (`package/kernel/src/projection/generic/Searching.jl:54`), and
> `WorkbenchSearcher` still holds only `selection`
> (`package/domain/src/document/Workbench.jl:185-187`) with the panel rendering `nothing`
> (`package/domain/src/projection/primitive/WorkbenchToWidget.jl:299-304`).

1. **Make `SearchingProjection` configurable.** Its `pattern` is a plain `Regex`,
   not a `Cell` (`generic/Searching.jl:52-64`), so `ProjectionConfiguringProjection`
   can't generate an editable control for it. Give it a reactive `pattern::Cell`
   (like `TextFiltering`/`TextHighlighting`) and rebuild the match `CellVector`
   reactively from it. This is the prerequisite for the searcher panel's control
   bar to work.

2. **`WorkbenchSearcher` panel renders a configured search.** It currently holds
   only `selection` (`document/Workbench.jl:223-227`) and
   `WorkbenchSearcherToWidgetScrollPane` renders `nothing`
   (`WorkbenchToWidget.jl:297-302`) with all three `map_reference_*` /
   `projection_read` returning `nothing`. Change the panel projection to wrap a
   `ProjectionConfiguringProjection(inner = SearchingProjection(...))` over the
   search target, render its widget output, and route events through the
   configuring projection's reader (the control bar handles pattern editing /
   `Ctrl+F` / `Escape`; remaining structure needs the panel's own reference maps).

3. **(Optional) Shared `pattern::Cell` for cross-panel search.** If the searcher's
   pattern should also drive the editors' highlighting/filtering, construct one
   `pattern::Cell` in `make_workbench_document_example` and pass the *same* object
   to the searcher's `SearchingProjection` and each editor's configured
   `TextHighlighting`/`TextFiltering`. Otherwise each configured projection owns
   an independent control bar.

## Implementation phases

> Per repo convention: do the work in a git worktree, commit per phase, mark
> each phase done here as it lands, and move this file to `plan/done/` when
> complete.

### Phase 1 — Configured text highlighting in the workbench (class A, lowest risk)
**⏳ OPEN (verified 2026-06-23):** `combined_w2g` in `make_workbench_projection_example`
(`package/example/src/projection/Workbench.jl:19-47`) has no `ProjectionConfiguringProjection`
or `TextHighlighting` entry; no grep match for either symbol in the workbench example files.
- Wrap a text-bearing chain (start with the Console, then JSON/XML/Text editors)
  in `ProjectionConfiguringProjection(inner = …→TextHighlighting())` followed by
  the renderer stage, per the class-A snippet above. Idle until the user sets a
  pattern in the control bar.
- This reuses `make_text_configuring_projection`'s structure
  (`example/src/projection/Wrapper.jl`); factor a workbench-appropriate renderer
  (or reuse `combined_w2g`'s shape).
- Verify: `test_example` on the affected domains and a workbench print/read smoke
  test. Highlighting must not perturb navigation (its selection map is identity
  on offsets). Confirm `Ctrl+F` toggles the control bar and editing the pattern
  re-highlights live.

### Phase 2 — Wire the Searcher panel (class C, the control point)
**⏳ OPEN (verified 2026-06-23):** `WorkbenchSearcherToWidgetScrollPane.projection_print`
still wraps `nothing` (`package/domain/src/projection/primitive/WorkbenchToWidget.jl:299-304`);
`SearchingProjection` is not yet `Cell`-reactive (infra step 1, same status).
- Make `SearchingProjection` reactive on a `pattern::Cell` (infra step 1).
- Change `WorkbenchSearcherToWidgetScrollPane` to project a
  `ProjectionConfiguringProjection(inner = SearchingProjection(...))`: the control
  bar is the query input, the result `CellVector` renders below. Implement the
  panel's `map_reference_*` / `projection_read` (route through the configuring
  reader).
- (Optional) share the searcher's `pattern::Cell` with Phase 1's highlighters so
  one query drives both. Test: `test_repl` on the workbench example; assert
  pattern editing repopulates the result list (and, if shared, the highlight).

### Phase 3 — Configured text filtering (class A), separate mode
**⏳ OPEN (verified 2026-06-23):** No `TextFiltering` / `ProjectionConfiguringProjection`
entry in `combined_w2g` (`package/example/src/projection/Workbench.jl:19-47`); no grep match
in the workbench example files.
- Add a `ProjectionConfiguringProjection(inner = …→TextFiltering())` entry.
  Filtering changes the line set, so pick where it applies (e.g. the Console, not
  the code editors — filtering JSON lines breaks the syntax). Keep it as a
  distinct configured entry rather than stacking with highlighting in one chain
  (the standalone flags are mutually exclusive for the same reason). The control
  bar exposes `pattern` / `case_insensitive` / `invert`.

### Phase 4 — Clipboard (class B)
**⏳ OPEN (verified 2026-06-23):** No `ClipboardSlice` / `ClipboardCollection` wrapping in
`make_workbench_document_example` and no dispatch entry in `combined_w2g`; no grep match for
either symbol in `package/example/src/document/Workbench.jl` or `.../projection/Workbench.jl`.
(The underlying projections exist at `package/domain/src/projection/primitive/ClipboardToAny.jl`.)
- Wrap the JSON and XML editor contents in `ClipboardSlice`
  (and/or a `ClipboardCollection` editor) in
  `make_workbench_document_example`.
- Add `ClipboardSlice => ClipboardSliceToAnyProjection()` and
  `ClipboardCollection => ClipboardCollectionToAnyProjection()` entries to
  `combined_w2g`.
- The toggle ops drop `editor.iomap`; confirm that interacts correctly with the
  workbench's forward-projected selection cells. Test: `test_repl` +
  copy/cut/paste gesture sequence (mirror `clipboard_example` coverage).

### Phase 5 — Dragging (class B)
**⏳ OPEN (verified 2026-06-23):** No `DraggingState` wrapping and no `DraggingState` dispatch
entry in `combined_w2g`; no grep match in the workbench example files. (The decorator exists at
`package/domain/src/projection/higherorder/Dragging.jl`.)
- Wrap a list-bearing node (a JSON array editor, or the panel list of a page) in
  `DraggingState`; add `DraggingState => DraggingProjection()` to `combined_w2g`.
- Drop target resolution depends on the graphics layer hit-testing `MouseUp`
  (see `higherorder/Dragging.jl` docstring + `plan/done/dragging.md` Phase 1).
  Confirm that landed; otherwise a live drop is a no-op and only the synthetic
  test exercises it.

### Phase 6 — Tooltip (class C)
**⏳ OPEN (verified 2026-06-23):** The `tooltip && workbench` error still exists, now at
`package/example/src/Examples.jl:274-275` (not line 220). No `TooltipSource` wrapping or
dispatch entry in the workbench example files. (The decorator exists at
`package/domain/src/projection/higherorder/TooltipDecorator.jl`.)
- Remove the `tooltip && workbench` error in `run_example` (`Examples.jl:220`),
  or add a dedicated workbench-tooltip wiring path.
- Wrap a chosen sub-node (descriptor target, or each editor) in `TooltipSource`;
  add a `TooltipSource => TooltipDecoratorProjection(...)` dispatch entry with a
  `position` derived from the node geometry.
- The existing `ScreenDocument` → `WindowManagerProjection` pipeline already
  applies the bubbled open/close ops; verify the tooltip window opens as a
  sibling of the workbench window. Test: drive a selection that arms the trigger
  and assert an `OpenWindowOperation` reaches the window manager.

## Open questions / decisions to make during implementation

- **Searcher scope:** search the whole workbench, or only the active editor?
  Whole-workbench is more impressive but the result paths must re-root through
  the workbench projection back to the live document; active-editor is simpler.
- **Filtering vs highlighting coexistence:** both reading the same pattern cell
  in the same chain would filter *and* highlight. Keep them as separate configured
  entries (per the standalone flags being mutually exclusive).
- **Where exactly to wrap for clipboard/dragging:** every editor, or a couple of
  showcase editors? Wrapping every editor is uniform but adds a transparent
  layer to each pipeline; start with one or two showcase documents.
- **Shared vs per-projection pattern:** one shared `pattern::Cell` (searcher
  drives editor highlight, "search everywhere") vs. each configured projection
  carrying its own independent control bar. The `ProjectionConfiguringProjection`
  control bar works either way; sharing is just passing the same `Cell` object.
- **Control-bar placement in the workbench:** `ProjectionConfiguringProjection`
  stacks the control bar inside each panel's content split. Confirm that reads
  well within the editor scroll panes, or consider hosting all the configuration
  bars in the (otherwise empty) `WorkbenchOperator` panel instead.
```
