# Application

> **Kind:** design · **Status:** current · **Stands on:** [shell.md](../shell/shell.md), [assistant.md](../assistant/assistant.md), [fileformat.md](../fileformat/fileformat.md)

The application slice of `ProjecturedPlatform` is the window of ProjecturEd: a Files pane, a tab for each open file, and an assistant beside them, built with the wrappers of `build_editor` and the chrome of the shell slice. This document says how the window and its tool set are built, how the command line of the `projectured` binary reads into it, how a build warms it up, and how it finds a backend with no dependency on one.

## How it works

### The window

`make_application_document(paths; root, assistant)` makes the document of the window: one file tab for each path in `paths`, each wrapped in its own `UndoBuffer` so `Ctrl+Z` takes back an edit in the file a person is looking at; a `Workspace` as the Files pane over `root`; and the `assistant`, when it is not `nothing`. `_make_application_pane_tree` puts them side by side in a `PaneTree`: the Files pane in a "Files" group, the open files in a second group, and, when there is an assistant, a third group for it. The Files pane and the files split 0.2/0.8 with no assistant, and 0.18/0.5/0.32 with one. The whole tree then sits inside one more `UndoBuffer`, so a change that belongs to no file — a splitter that moves, a tab that opens — can be taken back too, and the focus is seated on the first open file, or on the root row of the Files pane when no file is open.

`make_application_window(paths; root, assistant, status_bar, measure)` builds the document and the projection of `make_application_projection` with the wrappers that `make_application_wrappers(; root, assistant, status_bar, measure, appearance)` names once, for `run_application` and for this function alike: `undo` wraps the whole pane tree in a history, `shell` builds the chrome, `clipboard` gives the window the clipboard and the Alt+arrow walk, `gesture_help` and `command_palette` give F1 and Ctrl+Shift+P, and `gesture_log`, `message_log`, `frame_statistics` and `fault_log` fill the tools that show what the window records. `make_editor_parts` applies them with no backend and makes no editor, which is what a caller that draws its own window scene, such as a test or the warm-up, needs. [shell.md](../shell/shell.md) describes each wrapper and why the order is fixed. `status_bar = false` leaves out the status bar, for a video that shows what the window paints again, because the status bar changes with every move of the caret. The clipboard offers all seven of its gestures, cut and the view toggle included, because a person who edits a file expects Ctrl+X to cut.

The chrome is `make_window_menu_bar()`, `make_window_toolbar(; assistant, explorer)` and, unless `status_bar` is `false`, `make_window_status_bar(document)`. The toolbar's assistant button makes a fresh `Assistant` with the backend, the model and the greeting of the one the window opened with; a window with no assistant has no assistant button. Its explorer button lists `root`, the same folder the Files pane opens with.

### The content rows

`make_application_content_projections(; measure)` is the table `NaturalToGraphics` draws every tab with, in `extra`: `UndoBuffer` is invisible and prints what it holds; `TextDocument` word-wraps; `WorkspaceDocument` opens a file into a tab wrapped in `UndoBuffer`, because that choice is the window's and not the file-system slice's; `Assistant` chains its own widget projection to a `NaturalToGraphics` that carries the two conversation rows, `make_conversation_draft_row` and `make_conversation_row`; and `PrimitiveDocument` prints as prose. Every other document — a `JsonDocument`, a `JuliaDocument`, any domain a session loads — draws through the plain natural renderer that `make_application_projection` puts around the pane tree, so this slice names no domain.

### The assistant's API

`make_application_assistant(backend; model, context, llm)` makes the `Assistant` of the window: `backend` is one of `APPLICATION_ASSISTANTS` (`:ollama`, `:anthropic`, `:none`), and `:none` answers `nothing`. Its greeting, from `get_application_greeting_text(backend)`, says what the window shows and what the assistant needs to answer.

`make_application_api()` is what that assistant may write, and the whole of it: five vocabularies, concatenated and passed to `declare_api!`.

| Vocabulary | Where it comes from |
| --- | --- |
| the pane verbs that arrange the window | `make_pane_api()` |
| the widget names that build what a pane shows | `make_interface_api()` |
| the file verbs that open and save one | `make_file_api()` |
| the workspace this application lists, and how to read what a tab holds | named in `make_application_api` itself: `OpenFileOperation`, `Workspace`, `WorkspaceFolder`, `search_documents`, `get_wrapped_document`, `get_file_content`, `print_natural_text`, `parse_natural_text`, `insert_elements!`, `delete_elements!` |
| what each loaded domain registered for its own documents | `get_registered_assistant_api()` |

Each vocabulary is declared where its verbs are, so a second host that offers the same verbs states it once and this function only names which it wants. The last row is the open end: a domain's `__init__` registers names with `register_assistant_api!`, and `get_registered_assistant_api()` answers every one that is loaded, in the order of the registrations; [assistant.md](../assistant/assistant.md#the-api-a-loaded-package-offers) describes the registry, and the JSON domain's seven document types are the first user of it (see [json.md](../../domain/json/json.md)).

`APPLICATION_SYSTEM` is the editor's own instructions with one paragraph that names these verbs, and `make_application_system()` appends the section "Reach what a tab holds" of the orientation guide. `start_application!(editor; mcp, assistant, model)` declares `make_application_api()` and the undo and redo tools on `editor.tools` once the editor exists, and, with `mcp` on and an assistant, also binds the meaning model of the backend to the tools, so a search by description ranks by meaning for an MCP client too.

### The command line

`run_application_command(arguments; backends)` is what the `projectured` binary runs: it parses the command line with `parse_application_arguments`, opens the window with `run_application`, and answers the exit code — 0 when the window closes, 1 for a wrong command line, 2 when the program fails, with its stack printed first. `backends` maps a backend name to the function that makes it, for example `(sdl = SdlBackend, web = WebBackend)`; `--backend` accepts only those names, and the first one is the default.

| Option | What it sets |
| --- | --- |
| `[files...]` | the paths `run_application` opens, one tab each |
| `--backend=NAME` | which backend draws the window, when the binary holds more than one |
| `--assistant=ollama\|anthropic\|none` | the model backend of the assistant (default: the start settings, `ollama` at first), or no assistant |
| `--model=NAME` | the model of that backend (default: the start settings, else the backend's own default) |
| `--root=DIRECTORY` | the directory the Files pane lists (default: the current directory) |
| `--mcp` | start an MCP server at `http://127.0.0.1:9876/mcp` |
| `--mcp=[HOST:]PORT` | start an MCP server there instead |
| `--context=TOKENS` | how many tokens of the conversation the model may see (default: the start settings, else the backend's own default) |
| `--strict-fault-policy` | stop at the first fault and print its stack, instead of surviving it |

A path with no leading `-` is a file; an unknown option, or a value a keyword refuses, raises an error that `run_application_command` prints to `stderr` and turns into exit code 1.

`--assistant`, `--model`, `--context` and `--mcp` are `nothing` when the command line does not give them, and then the `StartSettings` of the settings file decide them: the assistant, the model, the context and whether the MCP server starts. A person sets these in the settings tab, and they take effect at the next start. `make_application_settings(file; fault_policy, assistant, model, context, mcp)` fills the settings from the defaults, the file, the environment and these values, in that order, and `run_application` reads the start settings from it. See [settings.md](../settings/settings.md).

`run_application(paths...; backend, assistant, model, mcp, mcp_host, mcp_port, root, context, width, height, fault_policy, measure)` is the function the command line calls, and a host can call it directly: it makes the assistant, builds the editor with `build_editor` and the wrappers of `make_application_wrappers`, so the message log, the frame statistics and the fault log fill themselves with no feed of the caller's own; calls `start_application!`; and runs `run_editor!`. The editor keeps the tooltip window and the context menu window at the screen: its `window` argument gives `inner_wrappers = [wrap_tooltip_window, wrap_context_menu_window]`. `backend = nothing` takes `default_backend()`.

### The warm-up of a build

`warm_application()` opens the application once with no window, over a temporary directory with one file of each of three formats (`.json`, `.md`, `.jl`) and one plain `.txt` file, on the backend `default_backend((:ConsoleBackend,))` finds. It then replays a short, fixed script of events: a key, a click that opens a file in the Files pane, Enter on a file, Ctrl+S, and a new tab made with `Ctrl+T` and Insert, typed one key at a time with a Backspace and a Delete on the way — the first key of a new tab's name buffer lists every document type it can make, and that list compiles a method for each type, so the warm-up pays that cost once instead of a person paying it on the first real tab. `evaluate_reachable_cells!` runs after the window is built and after each event, and reads every reactive `Cell` the printed output reaches (capped by `_WARMUP_WALK_MAX_DEPTH` and `_WARMUP_WALK_MAX_NODES`), so a build compiles the bodies of the cells and the closures of a printer, and not only the graph that holds them. A failure of the warm-up is logged with `@warn` and does not stop the build. [builder.md](../../tool/builder/builder.md) describes the build that runs it as its `@compile_workload`.

### `default_backend`

`default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend))` constructs a backend by reflection over the loaded `Backend` subtypes, with `compute_loaded_subtypes`, the subtype walk of the domain slice, which needs no `InteractiveUtils` (see [domain.md](../domain/domain.md)): it matches each name of `prefer`, in order, against a type's own name or its qualified name (`parentmodule(T)`, `.`, `nameof(T)`), and constructs the first one that is loaded. So a caller needs no dependency on a backend package, and no `:kind` key is coined for one. It raises an error, naming the backends that are loaded, only when none of `prefer` is. `run_application` calls it with no argument when `backend` is `nothing`; `warm_application` calls it with `(:ConsoleBackend,)` alone, because the warm-up must run with no display.

## How it fits

The application slice depends on the kernel and on the assistant, collection, conversation, domain, fileformat, filesystem, natural, pane, primitive, projection, screen, serialization, shell, style, text, tooltip, undo and widget slices of `ProjecturedPlatform`; `PLATFORM_SLICE_EDGES` in [PlatformSuite.jl](../../../../test/platform/PlatformSuite.jl) has the row.

**It names no domain, no backend and no adapter.** A document of a domain draws through the natural renderer, which each loaded domain registers itself with; the model of the assistant is asked for by the name of its backend, through `make_llm`; and the window's backend is the one a caller passes, or the one `default_backend` finds among the loaded packages. So the window shows every domain that a session loads, and a session decides what it holds by what it loads:

```julia
using Projectured, ProjecturedPlatform, ProjecturedSDL, ProjecturedOllama
run_application("data.json")
```

The Julia domain registers its own closed chain with the natural renderer, under the key `:julia_code` (see [julia.md](../../domain/julia/julia.md)), so that an object pasted into Julia code stays one leaf, `⟨title⟩`, in every natural renderer and not only in this one; without it, the renderer would recurse the pasted object into its own domain's table instead of `JuliaToSyntax`'s closing rule.

`run_application_command`, `warm_application` and `default_backend` are reachable as `ProjecturedPlatform.run_application_command` and so on; the umbrella `Projectured` does not re-export this slice, only the essential names of `ProjecturedPlatform.EssentialsModule`. `ProjecturedBuilder` names the first two as the `main` and the `workload` of the `projectured` binary, which loads `ProjecturedPlatform` and also holds `ProjecturedOllama`, `ProjecturedAnthropic`, `ProjecturedMCP` and the backend packages the build names; see [builder.md](../../tool/builder/builder.md).

## Design decisions

- **The application names no domain, no backend and no adapter.** Each of the three has a seam it reaches through instead: the natural renderer for a domain, `make_llm` for a model, `default_backend` for a backend. The rejected alternative named a handful of domains directly, as a row for each one's own type. This slice is part of `ProjecturedPlatform`, and every domain already depends on the platform, so a row that named a domain here would close a cycle; the natural renderer breaks it, because a domain registers its own row with the renderer instead of the renderer naming the domain. The gain beyond the cycle: a session shows every domain it loads, not only the ones this slice was written against.
- **The Julia domain, not this slice, registers the chip for a pasted object.** A plain natural renderer sends a child of a document back to its own table by its own type, so a document that is not Julia, pasted into Julia code, would draw as the reflected tree of its own domain instead of the one-leaf chip that `JuliaToSyntax`'s own closing rule, `Document => JuliaObjectToSyntaxLeaf()`, draws. Registering that chain in the Julia domain's own `__init__`, under `:julia_code`, means every natural renderer draws Julia code this way, and not only this window's.
- **The warm-up stays in this slice and calls `default_backend((:ConsoleBackend,))`, the same reflection every caller uses**, instead of naming `ConsoleBackend` directly or moving to the umbrella. The slice stays the one place that builds the application, and the umbrella holds no part of it.

## Usage

```julia
using Projectured, ProjecturedPlatform, ProjecturedSDL, ProjecturedOllama
run_application("notes.md", "data.json"; assistant = :ollama)
```

```julia
document, projection = make_application_window(["data.json"]; assistant = make_application_assistant(:none))
editor = build_editor(document, projection; backend = SdlBackend())
start_application!(editor)
run_editor!(editor)
```

- Examples: no example of its own; the application is the example, as the shell slice's own chrome is.
- Tests: `test/projectured/editor/ApplicationTest.jl`, `test_application()`. It covers the assistant pane and its declared API, the command line (`parse_application_arguments`, `run_application_command`), the warm-up, and the whole window: the first focus, a verb through the readers, every file format drawn, `Ctrl+S`, the menu bar and the toolbar, the evaluator opened from the toolbar, a noted object pasted into a form, and the Files pane.

## Limits

- A press on the Assistant button, once its tab has closed, opens a fresh `Assistant` through `make_application_assistant` with the backend, the model and the context of the window's own assistant: the conversation starts over at the greeting, because the window keeps no assistant of its own once its tab is gone.
- The menu bar has no Save, Reload, Command palette, Gesture help or clipboard items yet; see the Limits of [shell.md](../shell/shell.md).
- The Files pane's tree opens collapsed by default, so a scenario that scrolls to a file three folders deep finds nothing drawn yet to scroll to. Two assertions of `test_application()` are marked `@test_broken` for this reason, in "the Files pane scrolls a tree taller than its pane".
