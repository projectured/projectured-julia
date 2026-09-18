# Workbench Domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

<img width="1285" alt="Workbench example" src="../../../asset/image/example/workbench.png">

The workbench domain models an IDE-style workspace with an AI assistant as
one of its panels, alongside a file navigator, a console, and an editor
column. It is implemented in
[source/workbench/WorkbenchModule.jl](../../../source/workbench/WorkbenchModule.jl)
and rendered to widgets by
[source/workbench/WorkbenchToWidget.jl](../../../source/workbench/WorkbenchToWidget.jl).
A workbench is a high-level Document whose projection chain is

```
WorkbenchWorkbench ──WorkbenchToWidget──► WidgetShell ──WidgetToGraphics──► GraphicsCanvas
```

This is the largest demonstration in ProjecturEd of a multi-stage projection that
takes an application-level document all the way to pixels.

## Document types

Every row but the last subtypes `WorkbenchDocument` (`<: Document`).

| Type | Role |
|---|---|
| `WorkbenchWorkbench(navigation_page, editing_page, information_page, control_page)` | Top-level container; four pages |
| `WorkbenchPage(elements::CellVector)` | One column; holds a sequence of panels |
| `WorkbenchNavigator(workspace::Workspace)` | The "Navigator" panel — file/document tree |
| `WorkbenchConsole(content::TextBlock)` | The "Console" panel — text output |
| `WorkbenchDescriptor(content::Reference)` | The "Descriptor" panel — describes the node referenced by `content` |
| `WorkbenchOperator()` | The "Operator" panel |
| `WorkbenchSearcher()` | The "Searcher" panel |
| `WorkbenchEvaluator(content)` | The "Evaluator" panel — eval-print loop window |
| `WorkbenchEditor(content; title="", filename="", follow_end=false)` | An open document in the editing column; `follow_end` keeps the view pinned to the end (a growing log) |
| `Assistant(; conversation, input, draft, backend, model, system, api_key, context, status, collapse_thinking, llm)` | The "Assistant" panel. `<: Document` directly — a sibling slice ([assistant.md](../assistant/assistant.md)), not a `WorkbenchDocument`; the workbench special-cases it (`WorkbenchToWidget.jl`'s `_is_panel`) |

Each panel carries a `title` (class-level constant or per-instance for
`WorkbenchEditor`) that becomes the title-bar text in the widget output.

## Projection

`WorkbenchToWidget()` is the entry-point factory. Internally it uses
`RecursiveProjection(TypeDispatchingProjection(...))` to dispatch on the
workbench type, with one projection per panel:

| Projection | Output |
|---|---|
| `WorkbenchWorkbenchToWidgetShell` | `WidgetShell` containing the four pages |
| `WorkbenchPageToWidgetTabbedPane` | `WidgetTabbedPane` over the page's panels |
| `WorkbenchNavigatorToWidgetScrollPane` | `WidgetScrollPane` with a tree of labels |
| `WorkbenchConsoleToWidgetScrollPane` | `WidgetScrollPane` over text content |
| `WorkbenchDescriptorToWidgetScrollPane` | `WidgetScrollPane` describing a node |
| `WorkbenchOperatorToWidgetScrollPane` | `WidgetScrollPane` operator UI |
| `WorkbenchSearcherToWidgetScrollPane` | `WidgetScrollPane` search UI |
| `WorkbenchEvaluatorToWidgetScrollPane` | `WidgetScrollPane` REPL UI |
| `WorkbenchEditorToWidgetScrollPane` | `WidgetScrollPane` containing the editor's projected content |
| `AssistantToWidgetSplitPane` | `WidgetSplitPane` containing the assistant's projected content |

Each of these is exported, so a custom workbench layout can re-bind one
projection without touching the rest. `AssistantToWidgetSplitPane` lives in
`source/assistant/AssistantToWidget.jl`, not `source/workbench/` — the
workbench dispatches to it (`WorkbenchToWidget.jl`'s `_panel_forward`/
`_panel_backward`/type-dispatch table) but does not own it; see
[assistant.md](../assistant/assistant.md).

## Building a workbench

```julia
wb = WorkbenchWorkbench(
    WorkbenchPage([WorkbenchNavigator(Workspace())]),
    WorkbenchPage([WorkbenchEditor(my_doc; title = "main.json")]),
    WorkbenchPage([WorkbenchConsole(),  WorkbenchEvaluator()]),
    WorkbenchPage([WorkbenchOperator()]),
)

proj = ChainingProjection(
    WorkbenchToWidget(),
    WidgetToGraphics(font),
)
```

The result is a tree whose root is a `WorkbenchWorkbench`, whose
projection emits a graphics canvas the SDL backend can render.

## WorkbenchPage and PaneTree

`WorkbenchPage` (a fixed column of panels) is this domain's own tab
container. A second, more general tab/split-pane system,
`PaneTree`/`PaneGroup`/`PaneSplit`/`PaneTab` in `source/pane/` (see
[pane.md](../pane/pane.md)), coexists with it rather than replacing it: a
workbench document opens either directly (`WorkbenchWorkbench` at the window
root) or wrapped in a `PaneTree`, and code that must work either way — e.g.
`OpenWorkspaceFileOperation`, which the Navigator's "open file" gesture fires
— checks which one the window holds (`source/workbench/WorkbenchFile.jl`) and
routes accordingly.

## Workspace and WorkbenchFile

`WorkbenchNavigator(workspace::Workspace)` shows a `Workspace` — the
substrate type that maps a workbench file tree onto the real filesystem
(`WorkspaceToFileSystem`, its projection to a browsable `FileSystemDirectory`
tree). Opening a file from the Navigator reads it into a `WorkbenchEditor`
through `WorkbenchFile.jl`'s save/reload gestures (`Ctrl+S`/`Ctrl+O`), which
pick a binary or natural-text format by the file's extension.

## Selection across the workbench

Every workbench type carries a `selection::Reference` field, injected
automatically by `@document`. Because `WorkbenchEditor.content` holds an
arbitrary inner document, the selection path can descend straight through the
workbench tree into the user's file — e.g.

```
@reference editing_page.elements[1].content.entries[1].value.value{3}
```

means "in the active editor, character 3 of the value of the first JSON
object entry". This is the mechanism that lets a single global selection
mechanism address every cursor in the IDE.

**Keyboard focus follows this selection.** A raw key event (a printable
`KeyPress`, a `KeyDown`) is offered only to the panel the workbench selection
currently points at — so clicking into the JSON editor moves typing there rather
than leaving it in the assistant composer. The assistant composer manages its own
cursor and forward-projects no selection of its own, and its reader claims every
printable key; routing raw keys through the selected panel is what stops it from
swallowing keystrokes meant for another document. When nothing is selected the
composer keeps focus as the sensible default (so `ENTER` still submits a draft in
a freshly opened workbench). See the raw-event branch of
`WorkbenchWorkbenchToWidgetShell`'s `read_intent` in `WorkbenchToWidget.jl`.

## Where to look for the layout details

The columns, tab bars, scroll panes, and split pane geometry are all
expressed in `WorkbenchToWidget.jl` — the file is the canonical reference
for how a higher-level domain composes widget primitives. The widget tree
it builds then flows through `WidgetToGraphics` to produce the canvas.
