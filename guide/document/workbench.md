# Workbench Domain

The workbench domain models an IDE-style workspace. It is implemented in
[program/src/document/Workbench.jl](../../program/src/document/Workbench.jl)
and rendered to widgets by
[projection/primitive/WorkbenchToWidget.jl](../../program/src/projection/primitive/WorkbenchToWidget.jl).
A workbench is a high-level Document whose projection chain is

```
WorkbenchWorkbench ──WorkbenchToWidget──► WidgetShell ──WidgetToGraphics──► GraphicsCanvas
```

This is the largest demonstration in ProjecturEd of a multi-stage projection that
takes an application-level document all the way to pixels.

## Document types

All subtype `WorkbenchDocument` (`<: Document`).

| Type | Role |
|---|---|
| `WorkbenchWorkbench(navigation_page, editing_page, information_page)` | Top-level container; three columns |
| `WorkbenchPage(elements::CellVector)` | One column; holds a sequence of panels |
| `WorkbenchNavigator(folders)` | The "Navigator" panel — file/document tree |
| `WorkbenchConsole(content::TextText)` | The "Console" panel — text output |
| `WorkbenchDescriptor(content::ReferencePath)` | The "Descriptor" panel — describes the node referenced by `content` |
| `WorkbenchOperator()` | The "Operator" panel |
| `WorkbenchSearcher()` | The "Searcher" panel |
| `WorkbenchEvaluator(content)` | The "Evaluator" panel — eval-print loop window |
| `WorkbenchEditor(title, filename, content)` | An open document in the editing column |

Each panel carries a `title` (class-level constant or per-instance for
`WorkbenchEditor`) that becomes the title-bar text in the widget output.

## Projection

`WorkbenchToWidget()` is the entry-point factory. Internally it uses
`RecursiveProjection(TypeDispatchingProjection(...))` to dispatch on the
workbench type, with one projection per panel:

| Projection | Output |
|---|---|
| `WorkbenchWorkbenchToWidgetShell` | `WidgetShell` containing the three columns |
| `WorkbenchPageToWidgetTabbedPane` | `WidgetTabbedPane` over the page's panels |
| `WorkbenchNavigatorToWidgetScrollPane` | `WidgetScrollPane` with a tree of labels |
| `WorkbenchConsoleToWidgetScrollPane` | `WidgetScrollPane` over text content |
| `WorkbenchDescriptorToWidgetScrollPane` | `WidgetScrollPane` describing a node |
| `WorkbenchOperatorToWidgetScrollPane` | `WidgetScrollPane` operator UI |
| `WorkbenchSearcherToWidgetScrollPane` | `WidgetScrollPane` search UI |
| `WorkbenchEvaluatorToWidgetScrollPane` | `WidgetScrollPane` REPL UI |
| `WorkbenchEditorToWidgetScrollPane` | `WidgetScrollPane` containing the editor's projected content |

Each of these is exported, so a custom workbench layout can re-bind one
projection without touching the rest.

## Building a workbench

```julia
wb = WorkbenchWorkbench(
    WorkbenchPage([WorkbenchNavigator([...])]),
    WorkbenchPage([WorkbenchEditor(my_doc; title = "main.json")]),
    WorkbenchPage([WorkbenchConsole(),  WorkbenchEvaluator()]),
)

proj = SequentialProjection(
    WorkbenchToWidget(),
    WidgetToGraphics(),
)
```

The result is a tree whose root is a `WorkbenchWorkbench`, whose
projection emits a graphics canvas the SDL backend can render.

## Selection across the workbench

`selection::Reference` is present on every workbench type. Because
`WorkbenchEditor.content` holds an arbitrary inner document, the selection
path can descend straight through the workbench tree into the user's
file — e.g.

```
@reference editing_page.elements[1].content.entries[1].value.value{3}
```

means "in the active editor, character 3 of the value of the first JSON
object entry". This is the mechanism that lets a single global selection
mechanism address every cursor in the IDE.

## Where to look for the layout details

The columns, tab bars, scroll panes, and split pane geometry are all
expressed in `WorkbenchToWidget.jl` — the file is the canonical reference
for how a higher-level domain composes widget primitives. The widget tree
it builds then flows through `WidgetToGraphics` to produce the canvas.
