# The package documents

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../design/system-anatomy.md), [package-rules.md](../rule/package-rules.md), [domain-anatomy.md](../design/domain-anatomy.md)

This folder has one folder for each slice, and each folder has the design document of its package: how the package works, how it fits with the others, why it is built so, and how to use it. The tables below list every document. A few folders also hold a detail guide next to the design document.

The code of slice `<slice>` is in `source/<group>/<slice>/`, where the group is `kernel`, `platform`, `domain`, `backend`, `adapter` or `tool`, and its package is `Projectured<Slice>`; `package/Projectured<Slice>/` holds only the name, the dependencies and the include list. The cross-cutting guides are one level up, in [documentation/](../). Read [concepts.md](../design/concepts.md) and [system-anatomy.md](../design/system-anatomy.md) first, and [domain-anatomy.md](../design/domain-anatomy.md) before the document of a domain.

The documentation tool of the editor names a guide here `<slice>/<file>`, so `kernel/cell` and `widget/widget` do not collide. The bare names belong to the guides one level up.

## The engine

| Package | Documents |
| --- | --- |
| `ProjecturedKernel` | [architecture.md](kernel/architecture.md) and the other guides in `kernel/`: cells, documents, references, selection, operations, projections, devices and backends, the editor, the agent |

## The substrate

The packages below every domain. [package-rules.md](../rule/package-rules.md) has their dependency table.

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedCollection` | [collection.md](platform/collection/collection.md) | `CellVector`, `CellMatrix`, `CellTable` and `ListNode`, the reactive containers |
| `ProjecturedPrimitive` | [primitive.md](platform/primitive/primitive.md) | the primitive documents: strings, numbers, booleans |
| `ProjecturedSerialization` | [serialization.md](platform/serialization/serialization.md) | the `.pdoc` snapshot, the `.pred` format, the file contract and the multi-file project |
| `ProjecturedDomain` | [domain.md](platform/domain/domain.md) | `@domain`, the shared placeholder and insertion, and the completion by reflection |
| `ProjecturedStyle` | [style.md](platform/style/style.md) | colours, fonts, styled text, and the TrueType measurer |
| `ProjecturedComponent` | [component.md](platform/component/component.md) | the master-detail component document |
| `ProjecturedProjection` | [projection.md](platform/projection/projection.md), with [generic-projections.md](platform/projection/generic-projections.md) and [higher-order-projections.md](platform/projection/higher-order-projections.md) | the generic and the higher-order projections |
| `ProjecturedDragging` | [dragging.md](platform/dragging/dragging.md) | reorder by drag and drop |
| `ProjecturedFocus` | [focus.md](platform/focus/focus.md) | the focus walk and the whole selection by Alt+press |
| `ProjecturedGestureTracking` | [gesturetracking.md](platform/gesturetracking/gesturetracking.md) | runs the recognitions of gestures over the inputs |
| `ProjecturedMouseTargetTracking` | [mousetargettracking.md](platform/mousetargettracking/mousetargettracking.md) | the part under the pointer, and its crossings by route |
| `ProjecturedVersioning` | [versioning.md](platform/versioning/versioning.md) | the versions of a document |
| `ProjecturedPlot` | [plot.md](platform/plot/plot.md) | the axis arithmetic and the colour and marker cycles of the charts |
| `ProjecturedGraphics` | [graphics.md](platform/graphics/graphics.md) | the graphics documents, the hit test and the selection ring |
| `ProjecturedScreen` | [screen.md](platform/screen/screen.md) | the window model |
| `ProjecturedLayout` | [layout.md](platform/layout/layout.md) | rows, columns, grids, flows, stacks, anchored and constraint layouts |
| `ProjecturedText` | [text.md](platform/text/text.md) | styled text, the flat caret, and text to graphics |
| `ProjecturedWidget` | [widget.md](platform/widget/widget.md) | the widgets, their routing, and the object views |
| `ProjecturedReflection` | [reflection.md](platform/reflection/reflection.md), with [bounded-sync.md](platform/reflection/bounded-sync.md) | the view of any Julia value, and its bounded sync |
| `ProjecturedClipboard` | [clipboard.md](platform/clipboard/clipboard.md) | copy, cut, note and paste for any document |
| `ProjecturedPane` | [pane.md](platform/pane/pane.md) | tabs, split panes, and the pane tree of the window |
| `ProjecturedTooltip` | [tooltip.md](platform/tooltip/tooltip.md) | the tooltip in a window of its own |
| `ProjecturedNatural` | [natural.md](platform/natural/natural.md) | the natural notation of each domain, and the renderer of any document |
| `ProjecturedSyntax` | [syntax.md](platform/syntax/syntax.md) | the syntax tree, the insertion leaf, and syntax to text |
| `ProjecturedInspector` | [inspector.md](platform/inspector/inspector.md) | the inspector views of a reference and of the selection |
| `ProjecturedGestureHelp` | [gesturehelp.md](platform/gesturehelp/gesturehelp.md) | the help window and the command palette |
| `ProjecturedGestureLog` | [gesturelog.md](platform/gesturelog/gesturelog.md) | the log of the gestures of the session |
| `ProjecturedFileFormat` | [fileformat.md](platform/fileformat/fileformat.md) | the choice of a format by the file extension |
| `ProjecturedFault` | [fault.md](platform/fault/fault.md) | the fault barrier, the fault log and the safe mode |
| `ProjecturedConsole` | [console.md](backend/console/console.md) | the terminal backend |
| `ProjecturedPdf` | [pdf.md](backend/pdf/pdf.md) | the export to a vector PDF |
| `ProjecturedDisplay` | [display.md](platform/display/display.md) | a value shown in an editor beside the REPL |

## The domains

[domain-inventory.md](../design/domain-inventory.md) lists the twenty domains, their dependencies and their documents.

## The application

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedUndo` | [undo.md](platform/undo/undo.md) | the undo buffer and its history |
| `ProjecturedLog` | [log.md](platform/log/log.md) | the message log of the session |
| `ProjecturedStatistics` | [statistics.md](platform/statistics/statistics.md) | the frame statistics of the editor loop |
| `ProjecturedShell` | [shell.md](platform/shell/shell.md) | the wrappers and the chrome of a window |
| `ProjecturedHelp` | [help.md](platform/help/help.md) | the document types, the projections and the page about the program that the Help menu opens |

## The packages with a third-party dependency

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedSdl` | [sdl.md](backend/sdl/sdl.md) | the native window backend |
| `ProjecturedWeb` | [web.md](backend/web/web.md) | the browser backend |
| `ProjecturedVideo` | [video.md](backend/video/video.md) | the recording of a video |
| `ProjecturedAnthropic`, `ProjecturedOllama` | [llm.md](kernel/llm/llm.md) | the two language model backends |
| `ProjecturedOpenRouter` | [openrouter.md](adapter/openrouter/openrouter.md) | the relevance model on the Decisions API of OpenRouter |
| `ProjecturedMcp` | [mcp.md](adapter/mcp/mcp.md) | the MCP server |
| `ProjecturedTulip` | [tulip.md](adapter/tulip/tulip.md) | the constraint solver of the layout |
| `ProjecturedAdaptagrams` | [adaptagrams.md](adapter/adaptagrams/adaptagrams.md) | the native graph layout engine |
| `ProjecturedOdbc` | [database.md](domain/database/database.md) | the ODBC adapter and the live queries |

## The tools

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedRepl` | [repl.md](tool/repl/repl.md) | the leaf that a session loads, with the precompile workload |
| `ProjecturedBuilder` | [builder.md](tool/builder/builder.md) | the build of a native binary |
