# Enable clipboard, dragging, tooltip, text filtering, searching & highlighting in the workbench example

> **Status (2026-08-12): NOT STARTED.** None of the six features are wired
> into the workbench example — re-checked directly: no
> `TextHighlighting`/`TextFiltering`/`ProjectionConfiguring`/`ClipboardSlice`/
> `ClipboardCollection`/`DraggingState`/`TooltipSource` symbol appears anywhere
> in `package/workbench/example/projection/Workbench.jl` or
> `package/workbench/example/document/Workbench.jl`. Both shared-infrastructure
> prerequisites are also still open. One architectural change worth knowing
> before picking this up: `make_workbench_projection_example` no longer builds
> a locally-named `combined_w2g` `TypeDispatchingProjection` — the wiring point
> this plan repeatedly refers to by that name is now the `extra=Pair{Type,Any}[...]`
> table passed to `NaturalToGraphics(...)` inside
> `package/workbench/example/projection/Workbench.jl`. Paths below are
> corrected for the current per-domain package layout; the design and phase
> plan otherwise still apply unchanged.

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
`ProjectionConfiguringProjection`** (`package/widget/main/ProjectionConfiguring.jl`)
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
the `ChainingProjection(ProjectionConfiguringProjection(inner=…), renderer)`
shape (renamed from `SequentialProjection`) `make_text_configuring_projection`
already uses (`package/workbench/example/projection/Wrapper.jl:117-130`). One more consequence:
`ObjectToWidget` edits parameter **`Cell`s**, so a configured projection's tunable
parameters must be `Cell`-valued fields — see the `SearchingProjection` gap below.

## The three placement classes (the design answer)

ProjecturEd has exactly three ways a projection enters a running pipeline, and
each of our six features uses one of them:

### A. Configured `Text → Text` stages inside a per-document-type content chain

These are domain-preserving `Text → Text` projections that render a given
document type. In the workbench the chain lives in the per-type dispatch
table of `make_workbench_projection_example`
(`package/workbench/example/projection/Workbench.jl`; this plan calls that
table `combined_w2g` throughout — as of 2026-08-12 the function builds it as
the `extra=Pair{Type,Any}[...]` argument to `NaturalToGraphics(...)` rather
than a locally-named `TypeDispatchingProjection` variable, but the shape and
placement logic below are unchanged), e.g. the JSON entry today is
`Json → Syntax → Text → TextToGraphics`.

- **`TextFiltering`** (`package/text/main/TextFiltering.jl`) — drops non-matching lines.
- **`TextHighlighting`** (`package/text/main/TextHighlighting.jl`) — paints a swatch
  behind matches, keeping every line.

Both are **parameterised, so they are added via `ProjectionConfiguringProjection`**
(see above), not as a bare pipeline step. A configured JSON-with-highlighting
entry becomes:

```julia
JsonDocument => ChainingProjection(
    ProjectionConfiguringProjection(inner = ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextHighlighting(),          # idle until its pattern cell is set
    )),
    renderer,                         # widget+text → graphics (combined_w2g shape)
)
```

(`ChainingProjection` — renamed from `SequentialProjection` since this plan was
written, same shape.)

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
  (`package/clipboard/main/Clipboard.jl`) wrap `content`; `ClipboardSliceToAnyProjection` /
  `ClipboardCollectionToAnyProjection` (`package/clipboard/main/ClipboardToAny.jl`) dispatch
  on them. Ctrl+C/X/V/N + Ctrl+/ (slice display) / Ctrl+* (collection display).
  Generic over any content — wrap the structured editors (JSON/XML) where
  copying sub-documents is meaningful.
- **Dragging** — `DraggingState` (`package/dragging/main/Dragging.jl`) wraps `content`;
  `DraggingProjection` (`package/dragging/main/DraggingProjection.jl`) dispatches on it and emits a
  `MoveRangeOperation` to reorder a `CellVector`. Wrap a node with reorderable
  element lists (a JSON array, XML element children, or the page's panel list).

> These go **per-document, in the dispatch table**, because the behavior is
> attached to a specific sub-tree by wrapping it; the decorator is transparent
> everywhere else. They are still "generic" (work on any content), but their
> placement is local to whichever document the user wraps.

### C. The screen / workbench-general layer

These two are not local to one document — they cross panel boundaries or escape
to the screen root.

- **Tooltip** — `TooltipSource` (`package/tooltip/main/Tooltip.jl`) wraps `child`;
  `TooltipDecoratorProjection` (`package/tooltip/main/TooltipDecorator.jl`) dispatches on
  it but emits `OpenWindowOperation` / `CloseWindowOperation` that bubble all the
  way up to **`WindowManagerProjection` at the `ScreenDocument` root**. So a
  tooltip is a *screen-level* concern: it needs the screen pipeline
  (`run_example` already wraps the workbench in a `ScreenDocument` →
  `WindowManagerProjection(inner=ScreenToScreen())`). Today
  `tooltip=true && workbench=true` is an explicit error in `run_example`
  (`package/projectured/example/Gallery.jl:205`, re-verified 2026-08-12 — moved
  from `Examples.jl:220`, still present); lifting that restriction is part of
  this work.
  - Placement: wrap a chosen workbench sub-node (e.g. the descriptor target, or
    each editor) in a `TooltipSource`, and add a `TooltipSource` dispatch entry
    in `combined_w2g`. The decorator op bubbling is already handled by the
    existing screen pipeline `run_example` builds.

- **Searching** — `SearchingProjection` (`package/projection/main/Searching.jl`) is a deep,
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

*"Files touched" paths corrected 2026-08-12 to the current per-domain package
layout; `combined_w2g` still names the per-type dispatch table by the
convention this plan uses (see the status banner at the top of this file).*

| Feature | Mechanism | Config UI | Where it goes | Files touched |
|---|---|---|---|---|
| Text filtering | A: configured text stage | `ProjectionConfiguringProjection` | text chains in `combined_w2g` | `package/workbench/example/projection/Workbench.jl` |
| Text highlighting | A: configured text stage | `ProjectionConfiguringProjection` | text chains in `combined_w2g` | `package/workbench/example/projection/Workbench.jl` |
| Clipboard | B: wrapper + dispatch | none (gestures) | wrap structured editors; dispatch entry | `package/workbench/example/document/Workbench.jl`, `package/workbench/example/projection/Workbench.jl` |
| Dragging | B: wrapper + dispatch | none (gestures) | wrap a list-bearing node; dispatch entry | same two example files |
| Tooltip | C: screen-level | none (gestures) | wrap sub-node; dispatch entry; allow tooltip+workbench | both example files + `package/projectured/example/Gallery.jl` |
| Searching | C: workbench-general | `ProjectionConfiguringProjection` | `WorkbenchSearcher` projects to `ProjectionConfiguringProjection(SearchingProjection)` | `package/workbench/main/Workbench.jl`, `package/workbench/main/WorkbenchToWidget.jl`, example files |

## Shared infrastructure to build first

> **⏳ OPEN (re-verified 2026-08-12):** Neither infra step is done. `SearchingProjection.pattern`
> is still a plain `Regex` (`package/projection/main/Searching.jl:57`), and
> `WorkbenchSearcher` is an empty document (`@document struct WorkbenchSearcher <: WorkbenchDocument end`,
> `package/workbench/main/Workbench.jl:164-165` — even more minimal than the
> `selection`-only shape this plan describes) with the panel rendering an empty
> `WidgetScrollPane(nothing; ...)`
> (`package/workbench/main/WorkbenchToWidget.jl:387-392`).

1. **Make `SearchingProjection` configurable.** Its `pattern` is a plain `Regex`,
   not a `Cell` (`package/projection/main/Searching.jl:56-59`), so `ProjectionConfiguringProjection`
   can't generate an editable control for it. Give it a reactive `pattern::Cell`
   (like `TextFiltering`/`TextHighlighting`) and rebuild the match `CellVector`
   reactively from it. This is the prerequisite for the searcher panel's control
   bar to work.

2. **`WorkbenchSearcher` panel renders a configured search.** It currently is an
   empty document with no fields (`package/workbench/main/Workbench.jl:164-165`) and
   `WorkbenchSearcherToWidgetScrollPane` renders an empty scroll pane
   (`package/workbench/main/WorkbenchToWidget.jl:387-392`); its `map_reference_forward`/
   `map_reference_backward` both return `nothing` (lines 651, 713) and its
   `read_intent` (line 1015) only delegates through the generic
   `_retarget_panel_op` helper, no real search behavior. Change the panel
   projection to wrap a
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
**⏳ OPEN (re-verified 2026-08-12):** `combined_w2g` in `make_workbench_projection_example`
(`package/workbench/example/projection/Workbench.jl:2-51`) has no `ProjectionConfiguringProjection`
or `TextHighlighting` entry; no grep match for either symbol in the workbench example files.
- Wrap a text-bearing chain (start with the Console, then JSON/XML/Text editors)
  in `ProjectionConfiguringProjection(inner = …→TextHighlighting())` followed by
  the renderer stage, per the class-A snippet above. Idle until the user sets a
  pattern in the control bar.
- This reuses `make_text_configuring_projection`'s structure
  (`package/workbench/example/projection/Wrapper.jl`); factor a workbench-appropriate renderer
  (or reuse `combined_w2g`'s shape).
- Verify: `test_example` on the affected domains and a workbench print/read smoke
  test. Highlighting must not perturb navigation (its selection map is identity
  on offsets). Confirm `Ctrl+F` toggles the control bar and editing the pattern
  re-highlights live.

### Phase 2 — Wire the Searcher panel (class C, the control point)
**⏳ OPEN (re-verified 2026-08-12):** `WorkbenchSearcherToWidgetScrollPane`'s `print_document` (was `projection_print`)
still wraps `nothing` (`package/workbench/main/WorkbenchToWidget.jl:387-392`);
`SearchingProjection` is not yet `Cell`-reactive (infra step 1, same status).
- Make `SearchingProjection` reactive on a `pattern::Cell` (infra step 1).
- Change `WorkbenchSearcherToWidgetScrollPane` to project a
  `ProjectionConfiguringProjection(inner = SearchingProjection(...))`: the control
  bar is the query input, the result `CellVector` renders below. Implement the
  panel's `map_reference_*` / `read_intent` (was `projection_read`; route
  through the configuring reader).
- (Optional) share the searcher's `pattern::Cell` with Phase 1's highlighters so
  one query drives both. Test: `test_repl` on the workbench example; assert
  pattern editing repopulates the result list (and, if shared, the highlight).

### Phase 3 — Configured text filtering (class A), separate mode
**⏳ OPEN (re-verified 2026-08-12):** No `TextFiltering` / `ProjectionConfiguringProjection`
entry in `combined_w2g` (`package/workbench/example/projection/Workbench.jl:2-51`); no grep match
in the workbench example files.
- Add a `ProjectionConfiguringProjection(inner = …→TextFiltering())` entry.
  Filtering changes the line set, so pick where it applies (e.g. the Console, not
  the code editors — filtering JSON lines breaks the syntax). Keep it as a
  distinct configured entry rather than stacking with highlighting in one chain
  (the standalone flags are mutually exclusive for the same reason). The control
  bar exposes `pattern` / `case_insensitive` / `invert`.

### Phase 4 — Clipboard (class B)
**⏳ OPEN (re-verified 2026-08-12):** No `ClipboardSlice` / `ClipboardCollection` wrapping in
`make_workbench_document_example` and no dispatch entry in `combined_w2g`; no grep match for
either symbol in `package/workbench/example/document/Workbench.jl` or `.../projection/Workbench.jl`.
(The underlying projections exist at `package/clipboard/main/ClipboardToAny.jl`.)
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
**⏳ OPEN (re-verified 2026-08-12):** No `DraggingState` wrapping and no `DraggingState` dispatch
entry in `combined_w2g`; no grep match in the workbench example files. (The decorator exists at
`package/dragging/main/DraggingProjection.jl`.)
- Wrap a list-bearing node (a JSON array editor, or the panel list of a page) in
  `DraggingState`; add `DraggingState => DraggingProjection()` to `combined_w2g`.
- Drop target resolution depends on the graphics layer hit-testing `MouseUp`
  (see `package/dragging/main/DraggingProjection.jl` docstring + `plan/done/dragging.md` Phase 1).
  Confirm that landed; otherwise a live drop is a no-op and only the synthetic
  test exercises it.

### Phase 6 — Tooltip (class C)
**⏳ OPEN (re-verified 2026-08-12):** The `tooltip && workbench` error still exists, now at
`package/projectured/example/Gallery.jl:205` (moved twice: was `Examples.jl:220`,
then `package/example/src/Examples.jl:274-275`, now here). No `TooltipSource` wrapping or
dispatch entry in the workbench example files. (The decorator exists at
`package/tooltip/main/TooltipDecorator.jl`.)
- Remove the `tooltip && workbench` error in `run_example`
  (`package/projectured/example/Gallery.jl:205`),
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
