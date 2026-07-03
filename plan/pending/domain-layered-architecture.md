# Domain layered architecture — visual package extraction + feature-sliced domain

Design review of `package/domain` (2026-07-03): 116 files — 40 documents, 47 pipeline
projections, 6 parsers, 3 serializers, 2 backends, 3 editors — in one flat package with
folder-by-kind organization (`document/`, `parser/`, `projection/`, …). Reorganize it
into the same layered discipline as the kernel: a new **`ProjecturedVisual`** package
holding the rendering substrate, and a **feature-sliced `ProjecturedDomain`** where each
domain (json, sql, workbench, …) is one folder owning its document + parser +
projections + tests. Clarity, separate maintainability, and ease of understanding are
the priorities; backward compatibility is not a constraint, but all in-repo consumers
are updated in the same effort so the repo stays green.

Builds on [kernel-layered-architecture.md](kernel-layered-architecture.md) (the
kernel/base split) and extends its package chain:

```
kernel  →  base  →  visual  →  domain        (opt-in unchanged: sdl web odbc video tulip llm mcp)
engine     generic    rendering    feature slices
           machinery  substrate    (json, sql, workbench, …)
```

## Driving principles — package vs layer vs module vs file (decided)

Each level of the hierarchy answers to a different criterion. The question "should X
be a package?" is really four questions, one per level:

- **A package is a dependency or consumer boundary.** Unit of `Project.toml`,
  versioning, precompilation, and Pkg-enforced acyclicity. Create one **only** for a
  new external dependency, or for a distinct consumer set that wants the code
  *without* the rest. Every existing opt-in package obeys this (sdl=SDL2, web=HTTP,
  odbc=ODBC, tulip=C++ solver, llm/mcp=protocol clients). Cost of a package: a
  Project.toml, a slot in the resolver graph, alias plumbing in every dependent — so
  the criterion is strict, not aesthetic.
- **A layer is a direction-of-dependency boundary inside a package.** Unit of
  understanding order, tests, and docs: one folder, layer N imports only layers ≤ N,
  machine-enforced by the guard. Pure-Julia code with shared dependencies gets layers,
  not packages. A **feature slice** is a layer instance that groups by *feature*
  (a document with its parser, projections, tests) instead of by *kind* — used where
  cohesion is "these files change together", as in the domain tiers.
- **A module is a namespace and import-surface boundary.** Module names are de-facto
  public API (the umbrella re-exports every module's exports; domain aliases them by
  name), so module granularity = API granularity. Keep a module separate when it is a
  seam others import or implement against by name (`CollectionModule`,
  `BackendModule`); merge modules when they are only ever imported together and their
  separation just multiplies import headers (the kernel's 17-projection lesson).
- **A file is a readability boundary only.** A *fragment* file is `include`d by its
  module's aggregator and shares its namespace — zero API cost, so split freely by
  concept when a module grows. Never let file layout imply an API boundary that the
  module structure doesn't enforce.

Applying the package criterion here: `visual` earns a package on the **consumer**
clause — verified: `sdl` imports only {Color, Font, Geometry, Graphics, Image} + one
projection, `web` only {Color, Font, Geometry, Graphics} + Pdf/Sdl backends, `odbc`
only the SQL surface + the Sql→Syntax→Text→String chain. The backends already bind to
exactly this substrate and nothing else. The pure-Julia source domains do **not** earn
packages (no distinct dependencies, no distinct consumers) — they earn feature-slice
layers. Rejected alternatives: one package per domain (~20 Project.tomls for zero
dependency benefit), and themed multi-packages (data-formats/code/apps — boundaries
are arguable and buy nothing a slice folder doesn't).

## The dependency shape (verified 2026-07-03)

Extracted from all 115 source files' real `import ..Module` edges:

- **Documents never import other domains' documents.** Json, Xml, Yaml, Julia, Math,
  Book, Markdown, Sql, Graph, FileSystem, … have document out-degree 0 — all
  cross-domain coupling lives in the projections (the edges), not the documents (the
  nodes). This is what makes the slicing possible.
- **The rendering spine is real**: style atoms (Color ←42 importers, Font ←38,
  StyleText ←23, Geometry, Image, StyleStroke, ConstraintSolver) under render targets
  (Text ←44, Syntax ←19, Widget ←12, Graphics ←9, Layout ←8), self-contained (no source
  domain reaches in), and consumed by nearly every projection.
- **Every source domain funnels through Syntax** (or Widget), then
  SyntaxToText → TextToGraphics/TextToWidget → WidgetToGraphics/LayoutToGraphics.
- **Apps compose domains**: Workbench → {Text, Conversation, Workspace} + parsers +
  Llm/Mcp; Formula → Julia; Conversation/Evaluator → Text.
- `example/` and `test/` are already per-domain (`Json.jl`/`JsonTest.jl`,
  `SqlToSyntaxTest.jl`, …) — the feature slicing already exists everywhere except the
  source package.

### Projection-placement invariant — machine-verified

Rule: **home(projection) ≥ max(tier(input), tier(output), tier(every other import))**
under kernel < base < visual < domain(core < slices < serialization < apps). Verified
over all 115 files with the placement below: **zero violations except
`DocumentInsertionToSyntax` (see D1)**, and the domain slice→slice edges form a DAG
(no cycles): formula→julia, sql→json, conversation→{json,julia,xml},
serialization→{json,xml,sql,julia,math,book,filesystem}, workbench→{conversation,
serialization, parsers}.

Why it holds structurally: pipelines flow *specific → generic* (source document →
visual substrate), so a projection placed at its more-specific end always sees both
ends at-or-below itself. Reverse-direction projections (WorkspaceToFileSystem:
app-tier input → source-tier output) still obey the rule because the input is the
higher end.

The verification also **corrected the initial sketch**: the generic bridges
`ObjectToSyntax`, `CollectionToSyntax`, `PrimitiveToSyntax`, `PrimitiveToText`,
`ReferenceToText`, `ObjectToWidget` cannot live in `base` (their outputs Syntax/Text/
Widget live in visual, above base) — their least legal home is **visual**.

## Target packaging

### ProjecturedVisual (new, `package/visual`) — 3 layers, depends on kernel + base

| # | Folder | Contents | Story |
| --- | --- | --- | --- |
| 1 | `style/` | Color, Font, Geometry, Image, StyleText, StyleStroke, ConstraintSolver | pure value types every visual thing shares |
| 2 | `render/` | the five render-target documents Syntax, Text, Graphics, Widget, Layout + the spine-internal projections (SyntaxToText, SyntaxToWidget, TextToGraphics, TextToWidget, TextToString, WidgetToGraphics, LayoutToGraphics, CollectionToLayout, GraphicsCaching, the Text→Text decorators LineNumbering/TextFiltering/TextFirstLine/TextHighlighting/WordWrapping/SelectionInverting) + the generic→visual bridges (ObjectToSyntax, CollectionToSyntax, PrimitiveToSyntax, PrimitiveToText, ReferenceToText, ObjectToWidget) + widget decorators (WidgetHoverTracking, ProjectionConfiguring, WidgetPopupResolver) | how anything becomes visible |
| 3 | `backend/` | Console.jl (renders Text), Pdf.jl (renders Graphics) | the dependency-free concrete backends |

38 files total, all moved from `domain`. `sdl`/`web`/`video` re-point their domain
imports to `visual`; `odbc` re-points its SyntaxToText/TextToString imports.

### ProjecturedDomain — feature slices over 4 tiers

Tier rule inside the package: core(0) < source slices(1) < serialization(2) < apps(3);
slice→slice edges within tier 1 are allowed if acyclic (guard-checked, currently:
formula→julia, sql→json).

```
domain/src/
  ProjecturedDomain.jl        # kernel/base/visual alias preamble + slice includes

  core/              TIER 0   # shared cross-domain glue
    Document.jl               # DocumentCoreModule (shared insertion document)
    DocumentInsertion.jl      # the D1 registration seam (replaces DocumentInsertionToSyntax)

  json/              TIER 1   # each slice = document + parser + projections
    Json.jl · JsonParser.jl · JsonToSyntax.jl
  xml/       Xml.jl · XmlParser.jl · XmlToSyntax.jl
  yaml/      Yaml.jl · YamlParser.jl · YamlToSyntax.jl
  julia/     Julia.jl · JuliaParser.jl · JuliaToSyntax.jl
  math/      Math.jl · MathToSyntax.jl
  markdown/  Markdown.jl · MarkdownParser.jl · MarkdownToSyntax.jl
  book/      Book.jl · BookToSyntax.jl
  sql/       Sql.jl · SqlParser.jl · SqlToSyntax.jl · DbCatalog.jl · DbCatalogToSql.jl ·
             DbCatalogToSyntax.jl · Database.jl · DatabaseInstance.jl ·
             external/Database.jl · Tabular.jl · CellTableToTable.jl
  graph/     Graph.jl · GraphLayout.jl · GraphLayoutEngine.jl · GraphToGraphLayout.jl ·
             GraphLayoutToGraphics.jl
  filesystem/ FileSystem.jl · FileSystemToSyntax.jl · FileSystemToWidget.jl
  formula/   Formula.jl · FormulaToSyntax.jl                  (→ julia, sideways OK)
  gesturemap/ GestureMap.jl · GestureMapToSyntax.jl · GestureHelpDecorator.jl
  versioning/ Versioning.jl · VersioningToAny.jl
  clipboard/ Clipboard.jl · OsClipboard.jl · ClipboardToAny.jl
  dragging/  Dragging.jl (document) · Dragging.jl (decorator projection)
  tooltip/   Tooltip.jl · TooltipDecorator.jl
  inspector/ ReferenceInspector.jl · HoverProbe.jl · ReferenceInspectorToText.jl
  component/ Component.jl                                      (orphan — see D3)

  serialization/     TIER 2   # aggregates the text-serializable slices
    BinarySerialization.jl · NaturalFormat.jl · DocumentFile.jl · NaturalProjection.jl

  workbench/         TIER 3   # applications, compose slices below
    Workbench.jl · Workspace.jl · WorkspaceToFileSystem.jl · WorkbenchToWidget.jl ·
    WorkbenchFile.jl · WorkbenchAssistant.jl
  conversation/
    Conversation.jl · Evaluator.jl · ConversationToSyntax.jl · ConversationToWidget.jl ·
    ConversationEditor.jl
```

Module consolidation: **moves only, module names unchanged** in the first pass (the
domain alias block and all opt-in packages keep resolving); optional per-slice module
merges are a later cosmetic pass. Four files return to **base**: `ScreenToScreen.jl`
(ScreenDocument infra), `compound/Generic.jl`, `compound/HigherOrder.jl`,
`ProjectionTemplate.jl` (combinator aggregates with no document imports).

Edge-ownership rule (records the invariant): a projection X→Y lives with its
more-specific/higher-tier side — `JsonToSyntax`→json/, `SyntaxToText`→visual,
`ObjectToSyntax`→visual (generic input, visual output), `WorkbenchToWidget`→workbench/.

## Target file tree (folders, files, one-line descriptions)

Placement is the machine-verified map (see the invariant section); module names are
unchanged in the first pass. Files marked *(new)* are created by a refactor.

### `package/visual/` — the rendering substrate

```
src/
  ProjecturedVisual.jl          # top module: kernel/base alias preamble + 3 layer sections

  style/                        # LAYER 1 — pure value types every visual thing shares
    Color.jl                    # RGBA color value type + defaults/equality
    Font.jl                     # font descriptor (family, size, style)
    Geometry.jl                 # 2D points, sizes, rectangles
    Image.jl                    # bitmap image value type
    StyleText.jl                # styled-run text attributes (→ Font, Color)
    StyleStroke.jl              # stroke/outline style (→ Color)
    ConstraintSolver.jl         # the layout constraint solver (used by LayoutToGraphics)

  render/                       # LAYER 2 — the five render targets + spine projections
    Syntax.jl                   # tree-presentation domain: leaves/nodes, delimiters,
                                #   indentation, collapsibles — every source domain's target
    Text.jl                     # styled-text domain (TextText/TextString/TextNewline…)
    Graphics.jl                 # retained drawing domain (text/rect/canvas/viewport/image)
    Widget.jl                   # UI widget domain (labels, buttons, panes, menus…)
    Layout.jl                   # layout container domain
    SyntaxToText.jl             # flattens syntax trees to styled text (the shared step
                                #   many XToSyntax projections reuse helpers from)
    SyntaxToWidget.jl           # syntax → widget forms
    TextToGraphics.jl           # text → canvas + caret rendering
    TextToWidget.jl             # text → editable widget (→ TextToGraphics, WidgetToGraphics)
    TextToString.jl             # text → plain String (textualization endpoint)
    WidgetToGraphics.jl         # widget tree → canvas (the big one; → Layout, StyleStroke)
    LayoutToGraphics.jl         # layout → canvas via the constraint solver
    CollectionToLayout.jl       # base CellVector → layout container
    GraphicsCaching.jl          # graphics → graphics caching layer
    LineNumbering.jl            # Text→Text decorator: line-number gutter
    WordWrapping.jl             # Text→Text decorator: soft wrap
    TextFiltering.jl            # Text→Text decorator: row filter
    TextFirstLine.jl            # Text→Text decorator: first-line preview
    TextHighlighting.jl         # Text→Text decorator: match highlighting
    SelectionInverting.jl       # Text→Text decorator: inverted-selection rendering
    ObjectToSyntax.jl           # bridge: any Julia value → syntax tree (reflection)
    CollectionToSyntax.jl       # bridge: base collections → syntax tree
    PrimitiveToSyntax.jl        # bridge: base primitive docs → syntax tree
    PrimitiveToText.jl          # bridge: base primitive docs → text
    ReferenceToText.jl          # bridge: kernel references → text
    ObjectToWidget.jl           # bridge: reflection-driven editable form for Cell fields
    WidgetHoverTracking.jl      # decorator: hover state over widgets
    ProjectionConfiguring.jl    # decorator: editable parameter-control bar (→ ObjectToWidget)
    WidgetPopupResolver.jl      # decorator: resolves widget popups onto the screen

  backend/                      # LAYER 3 — the dependency-free concrete backends
    Console.jl                  # ANSI terminal backend rendering the Text domain
    Pdf.jl                      # SDL-free vector-PDF export of the Graphics domain

test/
  runtests.jl                   # guard: LAYERS = ["style","render","backend"]
  style/ · render/ · backend/   # migrated from ProjecturedTest: TextTest, SyntaxTest,
                                #   GraphicsTest, GeometryTest, SyntaxToTextTest,
                                #   TextToGraphicsTest, the Widget*Test family, …
doc/
  architecture.md · style.md · render.md · backend.md
```

### `package/domain/` — the feature slices

Each source slice follows the same shape — *document* (the data structure), *parser*
(text → document), *XToSyntax/XToWidget* (renders it) — so per-file comments below are
only given where a file departs from that pattern.

```
src/
  ProjecturedDomain.jl          # top module: kernel/base/visual alias preamble +
                                #   guard-checked tier/slice include order

  core/                         # TIER 0 — shared cross-domain glue
    Document.jl                 # DocumentCoreModule: the shared document-insertion document
    DocumentInsertion.jl        # (new, D1) the insertion registration seam; each slice
                                #   registers its own insertion rendering/parsing

  json/                         # TIER 1 — source slices (document + parser + projection)
    Json.jl · JsonParser.jl · JsonToSyntax.jl · JsonInsertion.jl (new, D1)
  xml/       Xml.jl · XmlParser.jl · XmlToSyntax.jl · XmlInsertion.jl (new, D1)
  yaml/      Yaml.jl · YamlParser.jl · YamlToSyntax.jl
  julia/     Julia.jl · JuliaParser.jl · JuliaToSyntax.jl · JuliaInsertion.jl (new, D1)
  math/      Math.jl · MathToSyntax.jl
  markdown/  Markdown.jl · MarkdownParser.jl · MarkdownToSyntax.jl
  book/      Book.jl · BookToSyntax.jl
  sql/       Sql.jl · SqlParser.jl · SqlToSyntax.jl · SqlInsertion.jl (new, D1)
             DbCatalog.jl                # database-catalog document
             DbCatalogToSql.jl           # catalog → SQL statements (domain-to-domain)
             DbCatalogToSyntax.jl
             Database.jl · DatabaseInstance.jl · DatabaseAdapters.jl (ex external/Database.jl)
                                         # adapter layer odbc plugs into (D3: wire here)
             Tabular.jl · CellTableToTable.jl   # tabular grid (D2: Json import smell)
  graph/     Graph.jl · GraphLayout.jl          # graph + laid-out-graph documents
             GraphLayoutEngine.jl               # the layout algorithm
             GraphToGraphLayout.jl · GraphLayoutToGraphics.jl
  filesystem/ FileSystem.jl · FileSystemToSyntax.jl · FileSystemToWidget.jl
  formula/   Formula.jl · FormulaToSyntax.jl    # spreadsheet-style formulas (→ julia/)
  gesturemap/ GestureMap.jl · GestureMapToSyntax.jl · GestureHelpDecorator.jl
                                         # gesture cheat-sheet document + help overlay
  versioning/ Versioning.jl · VersioningToAny.jl # object-versioning wrapper + passthrough
  clipboard/ Clipboard.jl · OsClipboard.jl · ClipboardToAny.jl
                                         # clipboard document, OS glue, paste projection
  dragging/  Dragging.jl (document) · DraggingProjection.jl (decorator; rename of
             projection/higherorder/Dragging.jl to break the twin basename)
  tooltip/   Tooltip.jl · TooltipDecorator.jl   # tooltip document + show/hide decorator
  inspector/ ReferenceInspector.jl · HoverProbe.jl · ReferenceInspectorToText.jl
                                         # live reference-inspection overlay
  component/ Component.jl                # orphan — D3: wire or delete

  serialization/                # TIER 2 — aggregates the text-serializable slices
    BinarySerialization.jl      # generic binary snapshot of any document
    NaturalFormat.jl            # textual round-trip via the slices' ToSyntax + parsers
    DocumentFile.jl             # extension-dispatched load/save entry point
    NaturalProjection.jl        # aggregate projection picking each type's natural rendering

  workbench/                    # TIER 3 — applications (compose the slices below)
    Workbench.jl                # the IDE-shell document (pages, navigator, console, …)
    Workspace.jl                # project/workspace document
    WorkspaceToFileSystem.jl    # workspace → filesystem view
    WorkbenchToWidget.jl        # the shell's widget rendering
    WorkbenchFile.jl            # load/save workbench state (→ serialization)
    WorkbenchAssistant.jl       # LLM assistant wiring (→ conversation, parsers, Llm/Mcp)
  conversation/
    Conversation.jl             # chat-conversation document
    Evaluator.jl                # code-evaluation document (assistant tool results)
    ConversationToSyntax.jl · ConversationToWidget.jl
    ConversationEditor.jl       # interactive conversation editing (→ parsers, Mcp)

test/
  runtests.jl                   # guard: tiers + acyclic slice→slice DAG check
  json/ · sql/ · … · workbench/ # per-slice tests migrated from ProjecturedTest
                                #   (JsonTest + JsonParserTest + JsonToSyntaxTest → json/, …)
doc/
  architecture.md               # tiers, slice DAG, the D1 seam, extension recipe
  slices.md                     # catalog: one section per slice
  core.md · apps.md
```

Returned to `package/base` (combinator aggregates with no document imports):
`ScreenToScreen.jl`, `compound/Generic.jl`, `compound/HigherOrder.jl`,
`ProjectionTemplate.jl`.

## The refactors

- **D1 — `DocumentInsertionToSyntax` (mandatory; the only invariant violation).**
  Today it imports Json+Xml+Sql+Julia documents *and parsers*, while
  `SqlToSyntax`/`JuliaToSyntax` import it back — a slices↔core knot (6 upward edges,
  the only ones in the package). Fix, mirroring kernel R1/R2: `core/DocumentInsertion.jl`
  keeps only the generic insertion document + a registration seam (an open generic or
  registry keyed by document type); each slice registers its own insertion rendering
  and parsing in its own files. After D1, core has zero upward imports and the slices
  don't import each other through insertion.
- **D2 — `CellTableToTable` imports Json (smell, decide at implementation).** Legal
  under slice ordering (sql→json is in the DAG) but conceptually odd. Either keep the
  edge and the ordering, or remove the Json dependency; look at the actual use first.
- **D3 — orphans.** Five files have no importers anywhere: `document/Component.jl`,
  `document/Tabular.jl`, `document/Database.jl`, `document/DatabaseInstance.jl`,
  `external/Database.jl` (DatabaseModule — no `..` imports either, but odbc reaches
  its submodules directly). Decision per file: wire into its slice (Database* +
  Tabular into sql/ — odbc uses them), or delete (Component, unless a plan claims it).
  Do not let orphans shape tiers.

## Guards, tests, docs (same discipline as the kernel plan)

- **Guards**: both packages get the kernel's fragment- and layer-aware
  `test/runtests.jl` guard. visual `LAYERS = ["style","render","backend"]`. domain
  layers = `["core", <slices...>, "serialization", "workbench", "conversation"]` with
  the addition the kernel guard doesn't need: **within tier 1, slice→slice edges are
  allowed but must be acyclic** (the guard computes the slice DAG and topo-sorts the
  include list accordingly).
- **Tests**: `package/visual/test/<layer>/` gets the spine tests migrated from
  ProjecturedTest (`TextTest`, `SyntaxTest`, `GraphicsTest`, `GeometryTest`,
  `SyntaxToTextTest`, `TextToGraphicsTest`, the Widget*Test family, …).
  `package/domain/test/<slice>/` gets each slice's tests (`JsonTest` + `JsonParserTest`
  + `JsonToSyntaxTest` → `test/json/`, …). ProjecturedTest keeps only cross-package
  integration (editor REPL loops, pipeline round-trips, backend rendering).
  `ProjecturedExample`'s per-domain files are the fixtures; examples stay in example/
  but its files map 1:1 onto slices.
- **Docs**: `package/visual/doc/` (architecture, style, render, backend) and
  `package/domain/doc/` (architecture + one page per slice is overkill — one
  `slices.md` catalog with a section per slice, plus `core.md` for the D1 seam and
  `apps.md` for workbench/conversation). Update repo-level `documentation/architecture.md`
  package diagram to the 4-package chain.

## Consumer updates

- **sdl/web/video**: re-point `ProjecturedDomain.XxxModule` imports for the 38 moved
  visual modules to `ProjecturedVisual.XxxModule` (sdl: Color/Font/Geometry/Graphics/
  Image + ClipboardToAny — note ClipboardToAny stays in domain/clipboard; web: + Pdf/Sdl
  backend modules; video: Graphics).
- **odbc**: re-points SyntaxToText/TextToString to visual; its SQL-side imports follow
  the sql/ slice (names unchanged).
- **umbrella** (`package/projectured`): the mechanical re-export loop iterates
  kernel + base + visual + domain (one more package in the loop).
- **domain's alias preamble**: gains `const XxxModule = ProjecturedVisual.XxxModule`
  aliases for the 38 moved modules so unmoved domain files keep their relative imports.
- **example/test**: import-path retargets per phase (grep-driven; module names don't
  change).

## Execution plan (phased; each lands green; requires the kernel plan's base package,
i.e. run after kernel P7 or later)

Verification per phase: **V1** `Pkg.test` of the touched packages (guards + layer
tests) · **V2** `julia --project=. -e 'using Projectured'` · **V3** the ProjecturedTest
functions touching the moved area (`test_json`, `test_sql`, `test_printers` samples).

- [ ] **Q0 — guards + orphan decision.** Stand up the visual/domain guard skeletons
      (LAYERS lists, slice-DAG check); decide D3 per orphan file (wire or delete);
      record D2 finding.
- [ ] **Q1 — visual package.** Create `package/visual` (Project.toml: kernel + base
      deps; alias preamble); `git mv` the 38 files into `style/`/`render/`/`backend/`;
      extend umbrella loop; add domain's visual aliases; re-point sdl/web/video/odbc;
      migrate the spine tests; `visual/doc/`. Biggest phase — land as 3 sub-commits
      (style → render+bridges → backends+consumers).
- [ ] **Q2 — D1 insertion seam.** Split `DocumentInsertionToSyntax` into the core
      seam + per-slice registrations (json/xml/sql/julia gain their insertion files);
      guard confirms core has no upward edges. Seam test with a toy registered type.
- [ ] **Q3 — slice folders.** `git mv` every remaining domain file into its slice
      folder per the placement table (moves only, module names unchanged); return the
      4 base-bound files to `package/base`; rewrite ProjecturedDomain.jl's include
      list into guard-checked tier/slice order.
- [ ] **Q4 — per-slice tests.** Migrate ProjecturedTest's per-domain files into
      `domain/test/<slice>/`; wire the per-slice runner (`Pkg.test(test_args=["json"])`);
      ProjecturedTest shrinks to integration.
- [ ] **Q5 — docs + closeout.** `domain/doc/` (architecture, slices catalog, core,
      apps); repo-level architecture.md 4-package diagram; supersede/cross-ref notes.

## Open decisions (implementation-time, non-blocking)

1. D2: keep or remove `CellTableToTable`'s Json dependency.
2. D3: per-orphan wire-or-delete (Component especially — nothing references it).
3. Whether `dragging/`, `tooltip/`, `inspector/`, `gesturemap/` (generic *interaction*
   features, not data domains) eventually graduate to `base` or a shared `interaction/`
   tier — they verify fine as slices; revisit only if they accumulate cross-slice users.
4. Per-slice module merges (JsonModule + JsonParserModule + JsonToSyntaxModule → one
   module per slice) as a later cosmetic pass, after the moves are proven green.
