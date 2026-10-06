# The package documents

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../design/system-anatomy.md), [package-rules.md](../rule/package-rules.md), [domain-anatomy.md](../design/domain-anatomy.md)

This folder has one folder for each slice, and each folder has the design document of its package: how the package works, how it fits with the others, why it is built so, and how to use it. The tables below list every document. A few folders also hold a detail guide next to the design document.

The code of slice `<slice>` is in `source/<group>/<slice>/`, where the group is `kernel`, `platform`, `domain`, `backend`, `adapter` or `tool`. A domain, a backend and an adapter is a package of its own, `Projectured<Slice>`, and `package/Projectured<Slice>/` holds only the name, the dependencies and the include list. A kernel or a platform slice is a module inside `ProjecturedKernel` or `ProjecturedPlatform`; the package holds every slice of its group. The cross-cutting guides are one level up, in [documentation/](../). Read [concepts.md](../design/concepts.md) and [system-anatomy.md](../design/system-anatomy.md) first, and [domain-anatomy.md](../design/domain-anatomy.md) before the document of a domain.

The documentation tool of the editor names a guide here `<slice>/<file>`, so `kernel/cell` and `widget/widget` do not collide. The bare names belong to the guides one level up.

## The kernel

| Package | Documents |
| --- | --- |
| `ProjecturedKernel` | [architecture.md](kernel/architecture.md) and the other guides in `kernel/`: cells, documents, references, selection, the mouse target, gestures, operations, projections, devices and backends, the editor, the agent |

## The platform

One package, `ProjecturedPlatform`, holds every slice below every domain. [package-rules.md](../rule/package-rules.md) has their dependency table.

| Slice | Document | What it holds |
| --- | --- | --- |
| `collection` | [collection.md](platform/collection/collection.md) | `CellVector`, `CellMatrix`, `CellTable` and `ListNode`, the reactive containers |
| `primitive` | [primitive.md](platform/primitive/primitive.md) | the primitive documents: strings, numbers, booleans |
| `serialization` | [serialization.md](platform/serialization/serialization.md) | the `.pdoc` snapshot, the `.pred` format, the file contract and the multi-file project |
| `domain` | [domain.md](platform/domain/domain.md) | `@domain`, the shared placeholder and insertion, and the completion by reflection |
| `style` | [style.md](platform/style/style.md) | colours, fonts, styled text, and the TrueType measurer |
| `appearance` | [appearance.md](platform/appearance/appearance.md) | the appearance of an editor in its view: the keys of the zoom and the scales, and the wrapper that prints the view again |
| `settings` | [settings.md](platform/settings/settings.md) | what a person chooses about how an editor works: the settings groups, their descriptions, and the operation that writes a setting and applies it |
| `settingsmanaging` | [settingsmanaging.md](platform/settingsmanaging/settingsmanaging.md) | the settings of an editor in its view: the root document that holds them, the wrapper that turns an edit of a setting into an applied setting, and the start step |
| `component` | [component.md](platform/component/component.md) | the master-detail component document |
| `projection` | [projection.md](platform/projection/projection.md), with [generic-projections.md](platform/projection/generic-projections.md) and [higher-order-projections.md](platform/projection/higher-order-projections.md) | the generic and the higher-order projections |
| `dragging` | [dragging.md](platform/dragging/dragging.md) | reorder by drag and drop |
| `focus` | [focus.md](platform/focus/focus.md) | the focus walk and the whole selection by Alt+press |
| `gesturetracking` | [gesturetracking.md](platform/gesturetracking/gesturetracking.md) | runs the recognitions of gestures over the inputs |
| `versioning` | [versioning.md](platform/versioning/versioning.md) | the versions of a document |
| `plot` | [plot.md](platform/plot/plot.md) | the axis arithmetic and the colour and marker cycles of the charts |
| `graphics` | [graphics.md](platform/graphics/graphics.md) | the graphics documents, the hit test and the selection ring |
| `dragtracking` | [dragtracking.md](platform/dragtracking/dragtracking.md) | keeps the part whose drag is on, and gives it the parts of its drag, wherever the pointer is |
| `screen` | [screen.md](platform/screen/screen.md), with [popup-window.md](platform/screen/popup-window.md) | the window model, and a menu, a dropdown list, a dialog, a tooltip and a context menu, each in a window of its own |
| `layout` | [layout.md](platform/layout/layout.md) | rows, columns, grids, flows, stacks, anchored and constraint layouts |
| `text` | [text.md](platform/text/text.md) | styled text, the flat caret, and text to graphics |
| `widget` | [widget.md](platform/widget/widget.md), with [context-menu.md](platform/widget/context-menu.md) | the widgets, their routing, the object views, and the context menu |
| `reflection` | [reflection.md](platform/reflection/reflection.md), with [bounded-sync.md](platform/reflection/bounded-sync.md) | the view of any Julia value, and its bounded sync |
| `clipboard` | [clipboard.md](platform/clipboard/clipboard.md) | copy, cut, note and paste for any document |
| `pane` | [pane.md](platform/pane/pane.md) | tabs, split panes, and the pane tree of the window |
| `tooltip` | [tooltip.md](platform/tooltip/tooltip.md) | the tooltip in a window of its own |
| `natural` | [natural.md](platform/natural/natural.md) | the natural notation of each domain, and the renderer of any document |
| `syntax` | [syntax.md](platform/syntax/syntax.md) | the syntax tree, the insertion leaf, and syntax to text |
| `inspector` | [inspector.md](platform/inspector/inspector.md) | the inspector views of a reference and of the selection |
| `gesturehelp` | [gesturehelp.md](platform/gesturehelp/gesturehelp.md) | the help window and the command palette |
| `gesturelog` | [gesturelog.md](platform/gesturelog/gesturelog.md) | the log of the gestures of the session |
| `fileformat` | [fileformat.md](platform/fileformat/fileformat.md) | the choice of a format by the file extension |
| `fault` | [fault.md](platform/fault/fault.md) | the fault barrier, the fault log and the safe mode |
| `filesystem` | [filesystem.md](platform/filesystem/filesystem.md) | the file system tree and the workspace of the Explorer |
| `display` | [display.md](platform/display/display.md) | a value shown in an editor beside the REPL |
| `essentials` | [essentials.md](platform/essentials/essentials.md) | the few names of the kernel and the platform that most users call, which the umbrella, each integration and each backend re-export |
| `undo` | [undo.md](platform/undo/undo.md) | the undo buffer and its history |
| `navigator` | [navigator.md](platform/navigator/navigator.md) | one page of a document at a time, with Back, Forward, Parent, an address and links |
| `log` | [log.md](platform/log/log.md) | the message log of the session |
| `mcplog` | [mcplog.md](platform/mcplog/mcplog.md) | the calls of the session that a client made over MCP |
| `task` | [task.md](platform/task/task.md) | a piece of work that runs as a task and ends with a result, in the words of `opp_repl`: its execution, a group of tasks, their documents and panes, the verbs, and how a domain adds a kind |
| `statistics` | [statistics.md](platform/statistics/statistics.md) | the frame statistics of the editor loop |
| `shell` | [shell.md](platform/shell/shell.md) | the wrappers and the chrome of a window |
| `help` | [help.md](platform/help/help.md) | the document types, the projections and the page about the program that the Help menu opens |
| `conversation` | [conversation.md](platform/conversation/conversation.md), with [transcript.md](platform/conversation/transcript.md) | the evaluator and the conversation documents |
| `assistant` | [assistant.md](platform/assistant/assistant.md) | the chat with a model beside the panes of a window |
| `application` | [application.md](platform/application/application.md) | the window of files, the Files pane and the assistant, and the command line of a binary |

## The domains

[domain-inventory.md](../design/domain-inventory.md) lists the eighteen domains, their dependencies and their documents.

## The backends

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedConsole` | [console.md](backend/console/console.md) | the terminal backend |
| `ProjecturedPDF` | [pdf.md](backend/pdf/pdf.md) | the export to a vector PDF |
| `ProjecturedSDL` | [sdl.md](backend/sdl/sdl.md) | the native window backend |
| `ProjecturedWeb` | [web.md](backend/web/web.md) | the browser backend |
| `ProjecturedVideo` | [video.md](backend/video/video.md) | the recording of a video |

## The adapters

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedAnthropic` | [anthropic.md](adapter/anthropic/anthropic.md) | the language model backend for a Claude model over the Anthropic API |
| `ProjecturedOllama` | [ollama.md](adapter/ollama/ollama.md) | the language model backend for a model on a local Ollama server, and its meaning vectors |
| `ProjecturedOpenRouter` | [openrouter.md](adapter/openrouter/openrouter.md) | the relevance model on the Decisions API of OpenRouter |
| `ProjecturedMCP` | [mcp.md](adapter/mcp/mcp.md) | the MCP server |
| `ProjecturedTulip` | [tulip.md](adapter/tulip/tulip.md) | the constraint solver of the layout |
| `ProjecturedAdaptagrams` | [adaptagrams.md](adapter/adaptagrams/adaptagrams.md) | the native graph layout engine |
| `ProjecturedODBC` | [odbc.md](adapter/odbc/odbc.md) | the ODBC adapter and the live queries |

## The tools

| Package | Document | What it holds |
| --- | --- | --- |
| `ProjecturedREPL` | [repl.md](tool/repl/repl.md) | the leaf that a session loads, with the precompile workload |
| `ProjecturedBuilder` | [builder.md](tool/builder/builder.md) | the build of a native binary |

## AutoIntegration

| Package | Document | What it holds |
| --- | --- | --- |
| `AutoIntegration` | [autointegration.md](autointegration/autointegration.md) | loads an installed package when its triggers are loaded, as the settings of the user choose |
