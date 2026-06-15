# Project consistency report

**Date:** 2026-06-13
**Scope:** Whole project — every guide in `guide/`, the top-level docs (`README.md`,
`CONTRIBUTING.md`, `CLAUDE.md`), and the source under `program/src/`, `example/src/`,
`test/src/`.
**Checks performed:**
1. **Documentation vs. code** — every concrete code claim in the docs (file paths,
   type names, fields, function/macro names, signatures, status tables, cross-links)
   checked against the actual code.
2. **Code self-consistency** — projection printer/reader/iomap completeness and
   bidirectionality, API argument order and parameter naming, document-type handler
   coverage, export/import integrity, and example ↔ document ↔ projection ↔ test
   coverage.

**Method:** Five focused audit passes, each evidence-based (every finding backed by a
`file:line`). The highest-impact findings were then independently re-verified against
the source. This is a read-only audit; no files were changed.

---

## Resolution status (2026-06-15)

The **High-severity** findings have been addressed:

- **RC-1 / RC-2 / RC-3 and all A/B/C doc High findings** — fixed across the guides
  (`projection_print` arg order, `evaluate_operation(editor, op)`, `run!`/`Screen`/
  `KeyDown`/`MousePress` vocabulary, per-domain constructor signatures,
  `ElementReference`/`PositionReference` taking `Int`, the `@reference_case`
  prefix-tail form, and `editor/annotation.md` marked aspirational).
- **E/High** — `test_filesystem_to_syntax()` is now called from `test_projections()`
  and exported; `FileSystemToSyntax` gained School-A `map_reference_forward`/
  `_backward` + reader (verified round-trip).
- **D/High (JuliaToSyntax)** — *partially addressed.* A full School-A mapper set was
  implemented and verified to compile/print, but it does **not** restore navigation
  on its own: Julia's dense projection-introduced structural tokens require the
  flat-offset projection-reference machinery (`_syntax_to_flat`) to be traversable,
  which JsonToSyntax has and JuliaToSyntax lacks. The experiment was reverted to avoid
  a navigation regression; an explanatory comment now documents the deferral in
  `JuliaToSyntax.jl`. **Follow-up:** wire flat-offset traversal + per-node School-A
  mappers to get real bidirectional Julia navigation.

### Medium-severity (2026-06-15)

Addressed:

- **A/Medium docs** — `architecture.md` inventory tables completed (33 widget
  types, 4 collection containers, 10 higher-order + 9 generic + ~33 primitive
  projections) and the insert/delete mapping status corrected
  (`CollectionInsertOperation`/`CollectionDeleteOperation` exist and are wired);
  `higher-order-projections.md` seven→ten; `generic-projections.md`
  FilteringProjection is fully implemented (not a stub) + SearchingProjection /
  ObjectToWidget added; `roadmap.md` broken link fixed.
- **B/Medium docs** — `widget.md` (theme signatures, factory maps all 33 types),
  `workbench.md` (four pages, `WorkbenchNavigator(Workspace)`), `collection.md`
  (four container types). (Several were already fixed during the High pass.)
- **C/Medium docs** — `devices-and-backends.md`, `editor/reference.md`,
  `debugging.md` (run_example window-size default), `testing.md` (mouse-click
  tests are run by `test_all`). (Most fixed during the High pass.)
- **D/Medium code** — `FileSystemToSyntax` backward mapper (done in the High
  pass); `BookInsertion`/`WidgetInsertion` printer handlers added
  (`BookInsertionToSyntaxLeaf`, `WidgetInsertionToGraphicsCanvas`) and registered
  so the type dispatcher no longer crashes on them.
- **E/Medium** — `lazy_example`/`lazy_bidirectional_example` are **intentionally**
  left out of the `examples` registry (they are infinite lazy lists that would
  hang the enumeration test suites); recorded in a code comment rather than
  registering them.

Deferred / out of scope:

- **D/Medium parameter-name unification** — large repo-wide rename tracked by its
  own plan `plan/pending/unify-projection-api-parameter-names.md`; left for that
  plan.
- Pre-existing (unrelated to this report): `test_typein(widget_example)` fails on
  `selector_element_pairs` tuple steps (`Tuple{String, Widget}` field access) on a
  clean checkout — a separate TypeinTest bug, not introduced here.

Low-severity findings remain open.

---

## Executive summary

The **code is internally very healthy**. Across ~56 projection files: argument order is
canonical in all 189 `projection_print` definitions, forward/backward reference mappers
are 100% paired, no projection references an undefined IO-map type, and the main module's
export/import block is sound (0 exported-but-undefined symbols, 0 imports of nonexistent
symbols, all ~140 font constants resolve). The real code defects are a small, specific
set (4 items).

The **documentation has drifted** from the code in three recurring ways that account for
most of the High-severity findings. A contributor copying current guide snippets would
write code that fails to compile or never dispatches. The three root causes (below) recur
across many guide files, so fixing each root fixes a cluster of findings at once.

### Severity counts

| Area | High | Medium | Low |
|---|---:|---:|---:|
| A. Architecture & system guides | 6 | 10 | 5 |
| B. Per-domain guides | 8 | 5 | 6 |
| C. Editor / reference / selection / REPL & test guides | 13 | 9 | 8 |
| D. Projection code self-consistency | 1 | 4 | 1 |
| E. Exports & example/test coverage | 1 | 1 | 2 |
| **Total (raw)** | **29** | **29** | **22** |

> Note: the doc High counts overlap heavily — three root causes (below) generate ~20 of
> the 27 doc-side High findings across different files. They are listed per-location so
> each is independently fixable, but they collapse to a handful of edits.

---

## Cross-cutting root causes (fix these first — highest leverage)

### RC-1 — `projection_print` argument order is mis-taught everywhere
**Canonical (code):** `projection_print(projection, recursion, input, context)` — recursion
**before** input ([api/Projection.jl:81](program/src/api/Projection.jl#L81); all 189 methods,
e.g. [JsonToSyntax.jl:51](program/src/projection/primitive/JsonToSyntax.jl#L51)).
**Docs teach:** `(projection, input, recursion, context)` — input before recursion.
A method written from the docs **never dispatches as intended.**
Recursion call: code is `projection_print(recursion, recursion, child, child_ctx)`; docs
show `(recursion, child, recursion, ctx)`.

Affected: [projection-system.md](guide/projection-system.md) (lines 10, 258, 298, 302–306, 339, 370),
[higher-order-projections.md](guide/higher-order-projections.md) (64, 101, 103),
[generic-projections.md](guide/generic-projections.md) (43, 64),
[design-decisions.md](guide/design-decisions.md) (63, 67),
[tutorial-new-domain.md](guide/tutorial-new-domain.md) (167–168, 203–204, 209).

### RC-2 — `evaluate_operation` argument order is reversed
**Canonical (code):** `evaluate_operation(editor, operation::Operation)` — editor **first**
([api/Operation.jl:22](program/src/api/Operation.jl#L22); methods in
[common/Operation.jl](program/src/common/Operation.jl#L32) obtain the document via
`editor.document`).
**Docs teach:** `evaluate_operation(operation, document)`.
Affected: [operations.md](guide/operations.md) (14, 25, 110–111),
[editor.md](guide/editor.md) (41, 64), [debugging.md](guide/debugging.md) (85–89).

### RC-3 — Stale entry-point and device/event vocabulary
The docs describe an `Application.jl` / `application(...)` entry point, a `Window` device in
`device/Window.jl`, backend `open_window!`/`close_window!` methods, and `MouseClick` /
`KeyPress(:symbol, ctrl)` events. **None of these exist.** Verified: no
`program/src/editor/Application.jl`, no `program/src/device/Window.jl`, no `application`
function, no `open_window!`/`close_window!` anywhere.
**Reality:** entry point is `run!(backend, projection, document; mcp=false)`
([Editor.jl:187](program/src/editor/Editor.jl#L187)); the output device is `Screen`
([device/Screen.jl:28](program/src/device/Screen.jl#L28)); windows are reconciled on demand
inside `write_to_devices`; mouse events are `MouseDown/MouseUp/MousePress/MouseMove/MouseScroll`
([device/Mouse.jl:25](program/src/device/Mouse.jl#L25)); character input is `KeyPress(::Char)`
and navigation is `KeyDown(key::Symbol, modifiers::Modifiers)`
([device/Keyboard.jl](program/src/device/Keyboard.jl#L92)).
Affected: [architecture.md](guide/architecture.md) (141, 144, 177),
[editor.md](guide/editor.md) (8, 56, 85–117), [devices-and-backends.md](guide/devices-and-backends.md)
(18–22, 32–57, 64, 87), [vision.md](guide/vision.md) (94–97), [debugging.md](guide/debugging.md) (85–89).

---

## A. Architecture & system guides

### `guide/architecture.md`
- **[High]** Layer-3 table (line 141) names `Application.jl` + `application()`. Neither exists.
  Real entry point is `run!` ([Editor.jl:151](program/src/editor/Editor.jl#L151)). *(RC-3)*
- **[High]** Layer-3 table (144) and dependency graph (177) name `device/Window.jl` / `Window`
  device / `QuitEvent`. No such file/type; `QuitEvent` is in
  [device/Screen.jl:38](program/src/device/Screen.jl#L38); the device is `Screen`. *(RC-3)*
- **[Medium]** "Mapping to original" table (231) marks insert/delete `❌`. Contradicted:
  `CollectionInsertOperation`/`CollectionDeleteOperation` exist, are evaluated
  ([common/Operation.jl:191](program/src/common/Operation.jl#L191)) and produced by JSON/XML readers.
- **[Medium]** Widget inventory (73) lists 15 of 33 widget types. Omits the Tier-1/Tier-2 set
  (`WidgetBadge`, `WidgetSwitch`, `WidgetSelect`, `WidgetAccordion`, `WidgetTable`, `WidgetTree`, …).
- **[Medium]** Collection row (81) omits `CellMatrix` and `CellTable` (both exported).
- **[Medium]** Primitive-projection table (113–134) lists ~18 of 33; omits `SqlToSyntax`,
  `PrimitiveToText`, `ReferenceToText`, `TextFiltering`, `TextHighlighting`, `ConversationToSyntax/ToWidget`,
  `LayoutToGraphics`, `WorkspaceToFileSystem`, `CellTableToTable`, `SqlToCellTable`, the `DbCatalog*`,
  `DatabaseInstanceToDbCatalog`, `DatabaseTableToTabularGrid`.
- **[Medium]** Higher-order table (88–97) lists 7 of 10; omits `WindowManagerProjection`,
  `TooltipDecoratorProjection`, `ProjectionConfiguringProjection`.
- **[Medium]** Generic table (100–108) lists 7 of 9; omits `SearchingProjection`, `ObjectToWidget`.
- **[Low]** Reference row (67) omits `PointReference`, `TextRectangularReference`; `ElementReference`/
  `PositionReference` are convenience constructors that produce `RangeReference`, not distinct structs.
- **[Low]** Reader-status (210–211) "character editing / mouse click ⚠️ partial" may understate the
  present wiring (verify against intended bar).

### `guide/projection-system.md`
- **[High]** Printer signature taught with input before recursion throughout. *(RC-1)*

### `guide/operations.md`
- **[High]** `evaluate_operation(op, document)` order reversed throughout. *(RC-2)*

### `guide/higher-order-projections.md`
- **[Medium]** "There are seven higher-order projections" — there are 10. *(missing 3, see A/architecture)*
- **[High]** Printer arg order in examples (64, 101, 103). *(RC-1)*
- **[Low]** "All five dispatchers…" wording vs more rows shown.

### `guide/generic-projections.md`
- **[Medium]** Labels `FilteringProjection` a "(stub)"/"scaffold"; it is fully implemented
  ([generic/Filtering.jl](program/src/projection/generic/Filtering.jl) — printer + both mappers + exported iomap).
- **[Medium]** Table omits `SearchingProjection` and `ObjectToWidget`.
- **[Low]** Printer arg order in one example (64). *(RC-1)*

### `guide/vision.md`
- **[Medium]** (94–97) Describes `Backend` as "two methods" then lists seven incl. nonexistent
  `open_window!`/`close_window!`. Real split: `Backend` = `init!`/`quit!`/`measure_text`
  ([api/Backend.jl:11](program/src/api/Backend.jl#L11)); `Device` = `write/read_to/from_device(s)`
  ([api/Device.jl:12](program/src/api/Device.jl#L12)). *(RC-3)*

### `guide/macros.md`
- **[Low]** `@projection struct AlternativeProjection …` example: `AlternativeProjection` is a plain
  `struct`, not `@projection`-generated ([higherorder/Alternative.jl:45](program/src/projection/higherorder/Alternative.jl#L45)).

### `guide/roadmap.md`
- **[Medium]** Broken link `../plan/further-development.md` → file is at `plan/tentative/further-development.md`.

### `guide/design-decisions.md`
- **[High]** Example printer signatures (63, 67) input-before-recursion and 4th arg named `ref`
  instead of a `PrinterContext`. *(RC-1)*

### Accurate (no material issues)
`guide/reactive-cells.md`, `guide/concepts.md`, `guide/design.md`, `README.md`, `CONTRIBUTING.md`,
`CLAUDE.md` — all cross-links resolve and named symbols exist. (`README` default model
`claude-opus-4-7` matches [Workbench.jl:260](program/src/document/Workbench.jl#L260); MCP port 9876 matches.)

---

## B. Per-domain guides

### `guide/document/json.md`
- **[High]** Reactive-update snippets (30–31) non-functional: `str.value[] = "world"` calls
  `setindex!` on a `String`; correct is `str.value = "world"`. `arr.elements[1][] = …` is wrong —
  `CellVector` `getindex` returns the value, not a `Cell`; use `arr.elements[1] = JsonString("b")`
  or `arr[1] = …`. Evidence: [common/Document.jl:78](program/src/common/Document.jl#L78),
  [Collection.jl:54](program/src/document/Collection.jl#L54).
- Otherwise accurate.

### `guide/document/syntax.md`
- **[High]** `SyntaxLeaf(open, value, close)` — actual order is `SyntaxLeaf(open, close, value)`
  ([Syntax.jl:232](program/src/document/Syntax.jl#L232)).
- **[High]** `SyntaxNode(open, close, sep, [children], true)` — actual is
  `SyntaxNode(open, close, sep, children; indentation::Int=0)`; `indentation` is an `Int` keyword,
  no positional `Bool` ([Syntax.jl:276](program/src/document/Syntax.jl#L276)).
- **[Low]** `.sep` is node-only, not on `SyntaxLeaf`.

### `guide/document/widget.md`
- **[High]** Multiple constructor signatures name nonexistent params/fields:
  `WidgetCheckbox(position, checked, content)` (no `checked`),
  `WidgetSplitPane(orientation, panes, splitter)` (fields are `elements`/`sizes`),
  `WidgetTabbedPane(tabs, active_index)` (arg is `selector_element_pairs`, no active-index field),
  `WidgetScrollPane(content, x_offset, y_offset)` (offset is `scroll_position`),
  `WidgetScrollBar(orientation, value, min, max, page)` (fields `value`/`thumb_size`),
  `WidgetButton/WidgetTooltip` missing required `size::Point2D`,
  `WidgetComposite(children)`/`WidgetMenu(items)` (take `position, elements`).
  Evidence: [Widget.jl:171–734](program/src/document/Widget.jl#L171).
- **[High]** Selection section (181) references nonexistent `x_offset`/`y_offset`; field is `scroll_position`.
- **[Medium]** Projection section: shows `WidgetToGraphics()` with no args (real:
  `WidgetToGraphics(font; measure, theme)`, [WidgetToGraphics.jl:2395](program/src/projection/primitive/WidgetToGraphics.jl#L2395)),
  and a dispatch table covering only the 15 core widgets (real table also maps the 17 extension widgets).
- **[Medium]** Per-widget projection description ("takes font, measure, foreground colour") is pre-theme-refactor;
  real signatures take `theme::WidgetTheme`.
- **[Low]** `ScrollWidgetOperation(scroll_pane, dx, dy)` → actual `(scroll_pane, scroll_delta)`; reader
  responds to `MousePress`, not nonexistent `MouseClick`.
- The widget *set* is current (all 32 types named correctly).

### `guide/document/workbench.md`
- **[High]** Projection table (55) names `WorkbenchAssistantToWidgetScrollPane`; real is
  `WorkbenchAssistantToWidgetSplitPane` ([WorkbenchToWidget.jl:770](program/src/projection/primitive/WorkbenchToWidget.jl#L770)).
- **[High]** `WorkbenchAssistant(content)` — constructor is keyword-only
  (`WorkbenchAssistant(; conversation, input, model, …)`); field is `conversation`
  ([Workbench.jl:296](program/src/document/Workbench.jl#L296)).
- **[Medium]** `WorkbenchWorkbench(...)` "three columns" — struct has four pages
  (adds `control_page`).
- **[Medium]** `WorkbenchNavigator(folders)` — constructor takes a `Workspace`
  ([Workbench.jl:116](program/src/document/Workbench.jl#L116)).
- **[Low]** `WidgetToGraphics()` no-arg won't construct.

### `guide/document/collection.md`
- **[Medium]** "two container types" / `CollectionDocument = Union{CellVector, ListNode}` — actually four:
  `Union{CellVector, CellMatrix, CellTable, ListNode}` ([Collection.jl:436](program/src/document/Collection.jl#L436)).
  `CellMatrix`/`CellTable` are exported but undocumented here.
- Otherwise accurate (all `CellVector`/`ListNode` API verified).

### `guide/document/graphics.md`
- **[Low]** "PNG output is a future extension" — `write_image` already supports `.png`
  ([Sdl.jl:867](program/src/backend/Sdl.jl#L867)).
- **[Low]** Generic field list says `width`/`height`; `GraphicsRect` uses `w`/`h`.

### `guide/document/xml.md`
- **[Low]** Guide is correct; note the *source* docstring [Xml.jl:16](program/src/document/Xml.jl#L16)
  is itself stale (says `.value[k]` where field is `cell`).

### Accurate (no material issues)
`guide/document/text.md` — all types/fields/constructors verified.

---

## C. Editor / reference / selection / REPL & test guides

### `guide/editor.md`
- **[High]** `application(...)` entry point + `Application.jl` (8, 85–108) — use `run!`. *(RC-3)*
- **[High]** `evaluate_operation(operation, document)` (41, 64) — reversed. *(RC-2)*
- **[High]** `Window` device + `open_window!`/`close_window!` (106, 112–117) — nonexistent;
  devices are `Device[Screen(), Keyboard(), Mouse()]` ([Editor.jl:190](program/src/editor/Editor.jl#L190)). *(RC-3)*
- **[Medium]** `MouseClick` in event list (56) — no such type. *(RC-3)*
- **[Low]** Shows 3-arg `projection_read`; loop uses 4-arg `Change`-based call ([Editor.jl:86](program/src/editor/Editor.jl#L86)).

### `guide/editor/reference.md`
- **[High]** `ElementReference(index::Cell)` / `PositionReference(index::Cell)` with `ElementReference(Cell(1))` —
  constructors take `Int` only; `ElementReference(Cell(1))` raises `MethodError`
  ([Reference.jl:68](program/src/reference/Reference.jl#L68)).
- **[Medium]** `FieldReference("a") + FieldReference("b")` "+"-notation (213, 237, 259, 69) — no `+`
  method exists for steps/paths; reads as runnable but fails.
- **[Medium]** "Multiple steps" example (100–105) passes a `ReferenceStep` as the `tail` of
  `ConcreteReferencePath`; `tail` must be a `ReferencePath`.
- **[Low]** `ProjectionReference(projection, step + step)` (69) — `+` nonexistent and `output_path`
  must be a path.
- Otherwise accurate (all step/path types, macros, helpers verified).

### `guide/editor/annotation.md`
- **[High]** Entire file documents an Annotation domain (`Annotation`, `AnnotationBindingDirect`,
  `AnnotationBindingReferencePath`, `AnnotationRegistry`, `get_annotation_registry`). **None exist
  anywhere** in `program/`, `example/`, or `test/` (verified). File is fully aspirational and not linked
  from any index. Recommendation: mark clearly as future/aspirational design, or remove.

### `guide/devices-and-backends.md`
- **[High]** Lists `Window` device in `device/Window.jl` — it's `Screen`. *(RC-3)*
- **[High]** `KeyPress(key::Symbol, ctrl::Bool)` / `KeyPress(:left, false)` — `KeyPress` takes a `Char`;
  navigation is `KeyDown(:left, Modifiers())` ([Keyboard.jl:92](program/src/device/Keyboard.jl#L92)). *(RC-3)*
- **[High]** `MouseClick(:left, …)` — nonexistent; use `MousePress`. *(RC-3)*
- **[Medium]** `open_window!`/`close_window!` in backend interface — nonexistent. *(RC-3)*
- **[Medium]** `sdl_to_mouse` — no such function; mapping is inline in `read_from_devices`
  ([Sdl.jl:1077](program/src/backend/Sdl.jl#L1077)). (`sdl_to_keypress`, `sdl_render_canvas` do exist.)
- **[Medium]** "Adding a new device" points to `ApplicationModule.application` — nonexistent; it's `run!`.

### `guide/debugging.md`
- **[High]** Manual printer/reader example (85–89): `projection_read(proj, iomap, KeyPress(:right, false))`
  + `evaluate_operation(op, doc)` — both fail (`KeyPress` char arg; `evaluate_operation` arg order). *(RC-2/RC-3)*
- **[Medium]** `run_example` "lives at Examples.jl:47" — actually defined at
  [Examples.jl:110](example/src/Examples.jl#L110)/153/371.
- **[Medium]** "default window size 2400×1600" — defaults to `sdl_display_size()` when unset
  ([Examples.jl:161](example/src/Examples.jl#L161)).
- **[Low]** `print_example` "at Examples.jl:75" — actually :396/:402.

### `guide/testing.md`
- **[Medium]** Claims mouse-click tests are "disabled in test_all" pointing to `ProjecturedTest.jl:63`.
  `test_mouse_clicks()` **is** called ([ProjecturedTest.jl:120](test/src/ProjecturedTest.jl#L120)); line 63
  is now an unrelated include.
- **[Low]** Several stale `file:line` anchors for walker helpers (function names all correct):
  `walk_printer_output` at PrinterTest.jl:115 (doc 75), `walk_reader_events` :51 (doc 32),
  `walk_repl_loop` :27 (doc 14), `_walk!` :45 (doc 25), `__init__` :13 (doc 10).
- **[Low]** `walk_printer_output` returns `(errors, status)` tuple; doc REPL example treats the raw
  return as `Vector{String}`.
- All named helpers exist and resolve.

### `guide/tutorial-new-domain.md`
- **[High]** Printer method signatures (167–168, 203–204) input-before-recursion. *(RC-1)*
- **[High]** Recursion call (209) `(recursion, child, recursion, ctx)` — should be
  `(recursion, recursion, child, child_ctx)`. *(RC-1)*
- **[High]** `@reference_case` pattern `entries[i] + rest =>` (226) — the macro parser has no `+` form;
  real prefix-binding is `entries[i].rest...` ([JsonToSyntax.jl:237](program/src/projection/primitive/JsonToSyntax.jl#L237)).
- Otherwise the registration steps and named APIs are correct.

### `guide/editor/selection.md`
- **[Low]** `using ReferenceModule` (64) — it's an internal submodule; use `using Projectured`.
- Otherwise accurate.

### `guide/selection-deep-dive.md`
- **[Low]** Snippets use `ElementReference(Cell(i))` (illustrative); real code uses `Int`.
- Otherwise accurate.

### Accurate (no material issues)
`guide/getting-started.md`, `guide/examples-tour.md` (all 6 example names + screenshots verified).

---

## D. Projection code self-consistency

### Strong consistency confirmed
- **Argument order:** all 189 `projection_print` definitions use canonical
  `(projection, recursion, input, context)`. 0 deviations.
- **Forward/backward mapper pairing:** 100% symmetric — every projection defining one direction
  defines the other.
- **IO-map presence:** no projection references an undefined IoMap type; specialised iomaps are
  defined in-file, generics in [common/IoMap.jl](program/src/common/IoMap.jl).
- **Math** (5/5) and **Julia** (30/30) document types fully covered by handlers; `JsonObjectEntry`/
  `XmlAttribute` "missing" handlers are intentional (rendered inside their parent node printer).

### Findings
- **[High]** `JuliaToSyntax` ([JuliaToSyntax.jl](program/src/projection/primitive/JuliaToSyntax.jl)) —
  35 sub-projections define `projection_print` but **zero** `map_reference_forward`/`map_reference_backward`/
  `projection_read` (verified: 0 mapper defs vs JsonToSyntax's 35). Node printers pass `Cell(nothing)`
  for output selection and the default `Projection` mappers don't descend through child iomaps, so
  **selection forward/back-mapping into nested Julia is unwired** — bidirectionality is broken for a
  live, tested example (`julia_example`). Unlike `ConversationToSyntax`, there is no acknowledging
  comment. Recommendation: implement per-node mappers delegating through stored child iomaps (the
  School-A pattern Json/Xml/Math/Book use), or add explicit `nothing` stubs + a comment if cursor
  support is genuinely deferred.
- **[Medium]** `FileSystemToSyntax` ([FileSystemToSyntax.jl:71](program/src/projection/primitive/FileSystemToSyntax.jl#L71)) —
  `FileSystemDirectoryToSyntaxNode` hand-wires forward selection *inside* `projection_print` but defines
  no `map_reference_backward` and no reader, so output→input mapping for directory children isn't wired.
  Also violates the recorded "Prefer School-A delegation" convention. Recommendation: move forward logic
  into `map_reference_forward` and add the symmetric backward mapper.
- **[Medium]** `BookInsertion` ([Book.jl:32](program/src/document/Book.jl#L32)) and `WidgetInsertion`
  ([Widget.jl:59](program/src/document/Widget.jl#L59)) — defined and exported but have **no printer
  handler** (verified: 0 references in `program/src/projection/`). Every sibling domain
  (`JsonInsertion`, `XmlInsertion`, `MathInsertion`) has one. Since `TypeDispatchingProjection`
  `error()`s on an unregistered type ([TypeDispatching.jl:50](program/src/projection/higherorder/TypeDispatching.jl#L50)),
  a document containing one would crash rather than render. Recommendation: add the handlers, or remove
  the unused types.
- **[Medium]** **Parameter-name inconsistency** (the subject of `plan/pending/unify-projection-api-parameter-names.md`,
  which is still entirely unexecuted): projection-arg slot `p` ×173 / unnamed ×20 / abbrevs ×11; printer
  input slot `input` ×31 vs ~40 ad-hoc single-letter names (`w` ×36, `b` ×19, `m` ×12, …); reference arg
  `reference` ×~100 vs `ref` ×~20; legacy reader payload `op` ×89 / `evt` ×47 / `payload` ×10 /
  `event` ×4 / `operation` ×1. Context arg `ctx` (×206) and `iomap` are already 100% consistent.
  Behaviour-neutral, but real and widespread.
- **[Low]** `ConversationToSyntax` reader deferral is **correctly documented** as intentional — cited only
  as the model of how a one-way stub should look (contrast with JuliaToSyntax). No action.

---

## E. Exports & example/test coverage

### Strong consistency confirmed
- Main module export/import block is sound: **0 exported-but-undefined symbols**, **0 imports of
  nonexistent symbols** (all 565 colon-imports resolve), all ~140 `font_*` constants + `StyleFont`/
  `make_style_font`/`color_default` resolve via whole-module `using`. All example/test builder files
  are included; all registered examples have builders.

### Findings
- **[High]** `test/src/projection/FileSystemToSyntaxTest.jl` — `test_filesystem_to_syntax()` is **included**
  ([ProjecturedTest.jl:36](test/src/ProjecturedTest.jl#L36)) but **never called by any runner and never
  exported** (verified: only the include line references it). Its `@testset` never executes — the
  FileSystem→Syntax marker tests are silently dead. Recommendation: call it from `test_projections()`
  and add to the export line.
- **[Medium]** `lazy_example` and `lazy_bidirectional_example` ([Examples.jl:72–73](example/src/Examples.jl#L72))
  are defined and exported, with builders present, but are **not in the `examples` registry array**, so
  every enumeration-based test (`test_printers`/`test_readers`/`test_selections`/`test_repls`/`test_examples`)
  skips them and they're unreachable by index. Recommendation: add both to the `examples` array (or
  document the exclusion).
- **[Low]** `make_tabular_document_example` ([Tabular.jl:1](example/src/document/Tabular.jl#L1)) — defined,
  included, exported, but referenced nowhere. Orphan builder; wire into an example/test or remove.
- **[Low]** 5 symbols colon-imported but not exported, where siblings are exported (possible oversight):
  `QuitEditorOperation`, `TextRectangularReference`, `WidgetScrollBarToGraphicsCanvas`,
  `WidgetToolbarToGraphicsCanvas` (`QuitEvent` is intentionally internal). Confirm intended visibility.

---

## Prioritized remediation

**Tier 1 — doc fixes that prevent broken copy-paste (cheap, high value):**
1. RC-1: fix `projection_print` arg order in 5 guides (one find/replace pattern per guide).
2. RC-2: fix `evaluate_operation` arg order in 3 guides.
3. RC-3: replace `Application.jl`/`application`/`Window`/`open_window!`/`MouseClick`/`KeyPress(:sym,…)`
   with `run!`/`Screen`/`MousePress`/`KeyDown(:sym, Modifiers())`/`KeyPress(::Char)` across
   architecture.md, editor.md, devices-and-backends.md, vision.md, debugging.md.
4. Fix the widget.md and workbench.md constructor signatures (B/High).
5. Fix syntax.md `SyntaxLeaf`/`SyntaxNode` constructor snippets and json.md reactive snippets.
6. Mark `guide/editor/annotation.md` as aspirational (or remove).

**Tier 2 — real code defects:**
7. Wire `JuliaToSyntax` reference mappers (D/High) — restores bidirectionality for the Julia example.
8. Add `BookInsertion`/`WidgetInsertion` handlers (or remove the types) (D/Medium) — prevents a runtime `error()`.
9. Add `FileSystemToSyntax` backward mapper (D/Medium).
10. Call `test_filesystem_to_syntax()` from `test_projections()` (E/High) — un-dead the test.
11. Register `lazy_example`/`lazy_bidirectional_example` (E/Medium).

**Tier 3 — consistency hygiene:**
12. Execute `plan/pending/unify-projection-api-parameter-names.md` (D/Medium).
13. Complete the architecture.md inventory tables and status flags (A/Medium ×several).
14. Refresh stale `file:line` anchors and minor wording (assorted Low).

---

## Appendix — independently re-verified High findings

The following were re-checked against source after the audit passes and confirmed:
`projection_print` canonical order ([api/Projection.jl:81](program/src/api/Projection.jl#L81));
`evaluate_operation(editor, operation)` ([api/Operation.jl:22](program/src/api/Operation.jl#L22));
JuliaToSyntax has 0 mappers (JsonToSyntax has 35); `FileSystemToSyntaxTest` included once, never called;
no `Application.jl`/`device/Window.jl`/`application`; annotation.md types absent from all source;
`BookInsertion`/`WidgetInsertion` have no projection handlers; `lazy_example`/`lazy_bidirectional_example`
defined at Examples.jl:72–73 but not in the registry array.
