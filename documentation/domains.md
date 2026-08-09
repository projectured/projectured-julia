# ProjecturedDomain — architecture

Contributor-facing guide to the internal structure of the
`ProjecturedDomain` package: the feature-slice organization, the slice DAG,
and what belongs where. For the whole-system picture (packages, layers, the
projection pipeline) see the repository-level
[documentation/architecture.md](../../../documentation/architecture.md);
this document is **only about domain**.

## Per-slice guides

Companion guides for individual domain slices live alongside this file:

- [json.md](json.md) — the JSON domain
- [rst.md](rst.md) — the reStructuredText domain
- [xml.md](xml.md) — the XML domain
- [chart.md](chart.md) — the chart domain
- [sequencechart.md](sequencechart.md) — the sequence chart domain
- [fsm.md](fsm.md) — the state machine domain
- [workbench.md](workbench.md) — the workbench application slice
- [versioning.md](versioning.md) — the versioning overlay

## What the domain package is

`ProjecturedDomain` holds every **concrete source domain** ProjecturEd
ships (JSON, XML, YAML, Julia, SQL, Math, Markdown, RST, Book, Graph, …), plus
the two application slices (`workbench`, `conversation`) that compose the
sources. It sits above the kernel (engine), the base (concrete engine
documents + doc-shaped projections + serialization), and the visual
(rendering substrate) packages in the dependency chain
`kernel ← base ← visual ← domain`.

Deps: `ProjecturedKernel`, `ProjecturedBase`, `ProjecturedVisual`, plus
`Base64` and `Markdown` from the stdlib. The opt-in backend packages
(`sdl`, `web`, `odbc`, `video`) depend on this package, not the other way
around.

## Feature slices

The package is organised as **feature slices** — each folder groups a
document with its parser, its `XToSyntax` bridge, and any related
decorators — instead of the old flat by-kind layout
(`document/`, `parser/`, `projection/`). A slice's files change together
and belong together. Cross-slice edges are allowed provided they form an
**acyclic slice DAG** (statically verified by the guard).

```
json/       Json.jl · JsonParser.jl · JsonToSyntax.jl
xml/        Xml.jl · XmlParser.jl · XmlToSyntax.jl
yaml/       Yaml.jl · YamlParser.jl · YamlToSyntax.jl
julia/      Julia.jl · JuliaParser.jl · JuliaToSyntax.jl
math/       Math.jl · MathToSyntax.jl
markdown/   Markdown.jl · MarkdownParser.jl · MarkdownToSyntax.jl
rst/        Rst.jl · RstParser.jl · RstToSyntax.jl · RstFile.jl
book/       Book.jl · BookToSyntax.jl
sql/        Sql.jl · SqlParser.jl · SqlToSyntax.jl
dbcatalog/  DbCatalog.jl · DbCatalogToSql.jl · DbCatalogToSyntax.jl
                                  (→ sql slice, sideways OK)
database/   Database.jl · DatabaseAdapters.jl
                                  (the adapter seam odbc plugs into)
tabular/    Tabular.jl · CellTableToTable.jl (→ json slice)
graph/      Graph.jl · GraphLayout.jl · GraphLayoutEngine.jl ·
            GraphToGraphLayout.jl · GraphLayoutToGraphics.jl
chart/      ChartGeometry.jl · Chart.jl · ChartPlot.jl ·
            ChartToChartPlot.jl · ChartPlotToGraphics.jl
sequencechart/
            SequenceChartGeometry.jl · SequenceChartRowReferenceStep.jl ·
            SequenceChart.jl · SequenceChartPlot.jl ·
            SequenceChartToSequenceChartPlot.jl ·
            SequenceChartPlotToGraphics.jl        (→ chart slice)
fsm/        Fsm.jl · FsmToSyntax.jl · FsmDiagram.jl · FsmToFsmDiagram.jl ·
            FsmDiagramToGraph.jl · FsmToJuliaCode.jl
                                  (→ julia slice for embedded code and
                                   codegen, → graph slice for the diagram)
filesystem/ FileSystem.jl · FileSystemToSyntax.jl · FileSystemToWidget.jl
formula/    Formula.jl · FormulaToSyntax.jl (→ julia slice)
gesturemap/ GestureMap.jl · GestureMapToSyntax.jl · GestureHelpDecorator.jl ·
            CommandPalette.jl · CommandPaletteToSyntax.jl ·
            CommandPaletteDecorator.jl
            (two views of one collected binding set: the help window shows it,
             the command palette runs it by name)
gesturelog/ GestureLog.jl · GestureLogToSyntax.jl · GestureLogRecorder.jl ·
            GestureLogOverlay.jl
versioning/ Versioning.jl · VersioningToAny.jl

workbench/  apps layer (above the source slices)
            Workbench.jl · Workspace.jl · WorkspaceToFileSystem.jl ·
            WorkbenchToWidget.jl · WorkbenchFile.jl · WorkbenchAssistant.jl
conversation/
            Conversation.jl · Evaluator.jl · ConversationToSyntax.jl ·
            ConversationToWidget.jl · ConversationEditor.jl
```

Plus **three transitional folders**, held here until their framework seams
land elsewhere:

- `projection/` — `ProjectionTemplate.jl` and `compound/{Generic,HigherOrder}.jl`.
  Land at kernel and base respectively once a children-container seam is
  added so kernel-side ProjectionTemplate no longer
  references `CellVector` by name.
- `serializer/` — `NaturalFormat.jl`, `DocumentFile.jl`. Land at
  `base/serialization/` once the framework/registration split turns the
  hardcoded per-format tables into per-slice registrations.
- `projection/primitive/` — `DocumentInsertionToSyntax.jl`,
  `NaturalProjection.jl`, `ScreenToScreen.jl`. Land at `visual/syntax/`
  and `base/document/` respectively once the insertion seam moves the
  insertion document down and the generic renderings up.

## Slice DAG (cross-slice edges within the source layer)

The cross-slice edges form a DAG:

- `formula → julia` — Formula uses JuliaModule types for its expressions
- `dbcatalog → sql` — DbCatalog renders through SqlToSyntax
- `tabular → json` — CellTableToTable renders json values in cells
  (kept; removing would require a shared primitive-cell
  type, larger surgery than the edge)
- `sequencechart → chart` — the sequence chart reuses the chart's axis
  scaling and tick selection (`ChartGeometryModule`), its colour cycle
  (`ChartModule`) and its marker shapes (`ChartPlotToGraphicsModule`),
  so the two read as one family rather than duplicating the arithmetic
- `fsm → julia` — guards/actions/entry code are JuliaDocument subtrees, and
  the code generator builds a JuliaDocument module
- `fsm → graph` — the state diagram prints into the graph slice

Everything else is within-slice or points at a lower package
(kernel/base/visual). The guard checks acyclicity statically.

## Membership tests

- **A file belongs in a source slice** if it names or renders a specific
  domain (Json, Xml, Sql, …) and changes together with the other files
  for that domain. If it names two domains, it belongs with the more
  specific one (the edge-ownership rule: `JsonToSyntax → json/`; a
  generic bridge like `ObjectToSyntax` belongs in visual, not domain).
- **A file belongs in the apps layer** (`workbench/`, `conversation/`) if
  it *composes* multiple source slices — Workbench pulls in
  Text/Conversation/Workspace and drives the IDE shell; Conversation is
  its own domain but couples heavily to Julia/parsers/Mcp so it lives at
  the app level.
- **A file does NOT belong in domain** if it targets no specific source
  domain — Sorting, Filtering, ObjectToWidget, etc. are generic and
  belong in base or visual.

## Testing

Per-slice tests will migrate to `test/<slice>/`. Until then, the
integration tests continue to run through `ProjecturedTest`. The
`ProjecturedTest` package houses cross-package pipeline round-trips
(printer/reader/text-navigation walks) that need the umbrella load.
