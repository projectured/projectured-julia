# Application

> **Kind:** design · **Status:** current · **Stands on:** [shell.md](../shell/shell.md), [assistant.md](../assistant/assistant.md), [fileformat.md](../fileformat/fileformat.md)

The application slice of `ProjecturedPlatform` is the window of ProjecturEd: an Explorer, a tab for each open file, and an assistant beside them, built with the wrappers of `build_editor` and the chrome of the shell slice. This document says how the window and its tool set are built, how the command line of the `projectured` binary reads into it, how a build warms it up, and how it finds a backend with no dependency on one.

## How it works

### The window

`make_application_document(paths; root, assistant)` makes the document of the window: one file tab for each path in `paths`, each wrapped in its own `UndoBuffer` so `Ctrl+Z` takes back an edit in the file a person is looking at; an `Explorer` over a section that holds the folder of `root`; and the `assistant`, when it is not `nothing`. `_make_application_pane_tree` puts them in a `PaneTree`: a main group whose first tab is the `Explorer`, followed by a tab for each file, and, when there is an assistant, a second group for it. The two groups split 0.68/0.32; with no assistant the main group fills the window. The whole tree then sits inside one more `UndoBuffer`, so a change that belongs to no file — a splitter that moves, a tab that opens — can be taken back too, and the focus is seated on the root row of the tree of the Explorer, also when files are open. So the window opens on the Explorer and the assistant, and the files are tabs behind the Explorer.

`start_application!` makes the first content of the explorer: `_fill_explorer_content!` calls `make_editor_explorer_content` (`ApplicationExplorer.jl`), which puts the entries that the window brought, such as its folder, before the open files, the task list and the assistant list of the editor, then the session document of each kind that a loaded package marks with `is_session_explorer_entry_type`, and the sections of the tools. `run_application` then reads the content that the state folder keeps for `root` (`get_explorer_content_file`, `load_explorer_content`) and replaces the first content with it when the file reads. It writes the content again after `run_editor!` returns (`save_explorer_content!`).

`make_application_window(paths; root, assistant, status_bar, measure)` builds the document and the projection of `make_application_projection` with the wrappers that `make_application_wrappers(; root, assistant, status_bar, measure, appearance)` names once, for `run_application` and for this function alike: `undo` wraps the whole pane tree in a history, `shell` builds the chrome, `clipboard` gives the window the clipboard and the Alt+arrow walk, `gesture_help` and `command_palette` give F1 and Ctrl+Shift+P, `gesture_log`, `message_log`, `frame_statistics`, `background_work` and `fault_log` fill the tools that show what the window records, and `assistant_list` links the Assistants pane to the tabs of the window. `make_editor_parts` applies them with no backend and makes no editor, which is what a caller that draws its own window scene, such as a test or the warm-up, needs. [shell.md](../shell/shell.md) describes each wrapper and why the order is fixed. `status_bar = false` leaves out the status bar, for a video that shows what the window paints again, because the status bar changes with every move of the caret. The clipboard offers all seven of its gestures, cut and the view toggle included, because a person who edits a file expects Ctrl+X to cut.

The chrome is `make_window_menu_bar()`, `make_window_toolbar(; assistant, explorer, files)` and, unless `status_bar` is `false`, `make_window_status_bar(document)`. The toolbar's assistant button makes a fresh `Assistant` with the backend, the model and the greeting of the one the window opened with; a window with no assistant has no assistant button. Its Explorer button reaches the `Explorer` tab. The shell option `files` makes the Files tool, a `WorkspaceExplorer` over `root`.

### The content rows

`make_application_content_projections(; measure)` is the table `NaturalToGraphics` draws every tab with, in `extra`: `UndoBuffer` is invisible and prints what it holds; `TextDocument` word-wraps; `WorkspaceDocument` opens a file into a tab wrapped in `UndoBuffer`, because that choice is the window's and not the file-system slice's; `Assistant` chains its own widget projection to a `NaturalToGraphics` that carries the two conversation rows, `make_conversation_draft_row` and `make_conversation_row`; and `PrimitiveDocument` prints as prose. Every other document — a `JsonDocument`, a `JuliaDocument`, any domain a session loads — draws through the plain natural renderer that `make_application_projection` puts around the pane tree, so this slice names no domain.

### The assistant's API

`make_application_assistant(backend; model, context, llm)` makes the `Assistant` of the window: `backend` is one of `APPLICATION_ASSISTANTS` (`:ollama`, `:anthropic`, `:acp`, `:none`). With `:none` the pane opens too: its greeting says that no model backend is chosen and where to choose one. A caller that wants no assistant pane, such as the recorder of a video, passes `assistant = nothing` to `make_application_document`. Its greeting, from `get_application_greeting_text(backend)`, says what the window shows and what the assistant needs to answer.

`make_editor_api()` is what the assistant of a window of the editor may write: the vocabularies that every window declares, concatenated and passed to `declare_api!`. The application declares the list as it is, and an application that builds on the editor adds the verbs of its own domain to it, so every window offers one vocabulary.

| Vocabulary | Where it comes from |
| --- | --- |
| the pane verbs that arrange the window | `make_pane_api()` |
| the widget names that build what a pane shows | `make_interface_api()` |
| the file verbs that open and save one | `make_file_api()` |
| the workspace of the folder of the window, and how to read what a tab holds | named in `make_editor_api` itself: `OpenFileOperation`, `Workspace`, `WorkspaceFolder`, `search_documents`, `get_wrapped_document`, `get_file_content`, `print_natural_text`, `parse_natural_text`, `insert_elements!`, `delete_elements!` |
| the arrangement and the roster of a collection | named in `make_editor_api` itself |
| the groups of tasks of the session | `make_task_api()` |
| a tree of documents, the processes of the system, the work of an agent | named in `make_editor_api` itself |
| what each loaded domain registered | `get_registered_assistant_api()` |

Each vocabulary is declared where its verbs are, so a host that offers the same verbs states it once and this function only names which it wants. The last row is the open end: a domain's `__init__` registers names with `register_assistant_api!`, and `get_registered_assistant_api()` answers every one that is loaded, in the order of the registrations; [assistant.md](../assistant/assistant.md#the-api-a-loaded-package-offers) describes the registry. A domain with a parser registers no constructors: a model reads and writes such a document as its text, with `print_natural_text` and `parse_natural_text`.

`EDITOR_SYSTEM` is the paragraph of the system text that names these verbs, and the system text of every window holds it. `APPLICATION_SYSTEM` is the editor's own instructions with one sentence about the window and `EDITOR_SYSTEM`, and `make_application_system()` appends the section "Reach what a tab holds" of the orientation guide. `register_editor_tools!(set)` adds the tools `undo`, `redo` and `take_picture`. `start_application!(editor; mcp, assistant, model)` declares `make_editor_api()` and these tools on `editor.tools` once the editor exists, and, with `mcp` on and an assistant, also binds the meaning model of the backend to the tools, so a search by description ranks by meaning for an MCP client too.

### The command line

`run_application_command(arguments; backends)` is what the `projectured` binary runs: it parses the command line with `parse_application_arguments`, opens the window with `run_application`, and answers the exit code — 0 when the window closes, 1 for a wrong command line, 2 when the program fails, with its stack printed first. `backends` maps a backend name to the function that makes it, for example `(sdl = SdlBackend, web = WebBackend)`; `--backend` accepts only those names, and the first one is the default.

| Option | What it sets |
| --- | --- |
| `[files...]` | the paths `run_application` opens, one tab each |
| `--backend=NAME` | which backend draws the window, when the binary holds more than one |
| `--assistant=ollama\|anthropic\|acp\|none` | the model backend of the assistant, an external agent (`acp`), or no backend yet (default: the start settings, `ollama` at first) |
| `--model=NAME` | the model of that backend (default: the start settings, else the backend's own default) |
| `--root=DIRECTORY` | the directory of the folder of the window (default: the current directory) |
| `--mcp` | start an MCP server at `http://127.0.0.1:9876/mcp` |
| `--mcp=[HOST:]PORT` | start an MCP server there instead |
| `--context=TOKENS` | how many tokens of the conversation the model may see (default: the start settings, else the backend's own default) |
| `--strict-fault-policy` | stop at the first fault and print its stack, instead of surviving it |
| `--agent-command=COMMAND` | the command line of the external agent of `--assistant=acp`, one argument that the shell quotes (default: the start settings, at first none, which starts the built-in Claude Code agent) |

A path with no leading `-` is a file; an unknown option, or a value a keyword refuses, raises an error that `run_application_command` prints to `stderr` and turns into exit code 1.

`--assistant`, `--model`, `--context`, `--mcp` and `--agent-command` are `nothing` when the command line does not give them, and then the `StartSettings` of the settings file decide them: the assistant, the model, the context, whether the MCP server starts, and the command of the external agent. A person sets these in the settings tab, and they take effect at the next start. `make_application_settings(file; fault_policy, assistant, model, context, mcp, agent_command)` fills the settings from the defaults, the file, the environment and these values, in that order, and `run_application` reads the start settings from it. See [settings.md](../settings/settings.md).

`run_application(paths...; backend, assistant, model, mcp, mcp_host, mcp_port, root, context, agent_command, width, height, fault_policy, measure)` is the function the command line calls, and a host can call it directly: it makes the assistant, builds the editor with `build_editor` and the wrappers of `make_application_wrappers`, so the message log, the frame statistics, the background work log and the fault log fill themselves with no feed of the caller's own; calls `start_application!`; and runs `run_editor!`. The editor keeps the tooltip window and the context menu window at the screen: its `window` argument gives `inner_wrappers = [wrap_tooltip_window, wrap_context_menu_window]`. `backend = nothing` takes `default_backend()`.

### The workload

The workload of the window runs gestures through the real loop of the editor, so that a package image holds the code that a person runs after the first window. `ApplicationWorkload.jl` holds it.

- `run_application_workload(files; steps, llm, timeout, backend)` starts the window as `run_application` does, with `_make_application_editor`, in a temporary folder that holds `files`. It reads no settings file, names no assistant backend, and starts no MCP server. It gives the steps one after the other, and then stops the loop.
- A step is a `WorkloadStep`: `WorkloadClick(target; button)`, `WorkloadKey(key; ctrl, shift, alt)`, `WorkloadTyping(text)` or `WorkloadWait(target)`. A target is `DrawnText(text; pick)`, a place where the window draws a text, or `DrawnPart(predicate)`, the drawing of a view whose input passes the predicate, such as a tool of the toolbar.
- Before each step, the window becomes quiet: for 0.25 s, no frame applies an input, and no wake, timer or input of the backend waits. Then a call on the task of the loop finds the target in what the window drew, with `find_workload_inputs(editor, step)`, and the workload sends the inputs to the backend with `send_workload_inputs!`. Another kind of step is a subtype of `WorkloadStep` with a method of `find_workload_inputs`.
- A step whose target the window does not draw in `timeout` seconds, and a fault that a barrier of the editor catches, make the workload throw an error that names each of them.
- `make_workload_llm(code; answer)` is the model of an assistant turn in a workload. Its first round asks the tool `execute_julia_code` to run `code`, and its second round says `answer`. Only a compile workload makes one.

Three lists use it. `run_window_workload(; backend)` runs the gestures of the window: a menu and an item of each menu, each tool of the toolbar, a text file and a `.pred` file opened and edited, the Explorer and its context menu, a new tab named in the name buffer, F1, the command palette, and an assistant turn. `run_file_workload(type; backend)` opens the file of `make_workload_file(type)` from the Files pane, clicks in it, types a key, saves, undoes, and opens the name buffer. `warm_application()`, the workload of the `projectured` binary, runs the window list and the file list of each type of `collect_workload_file_types()`. [package-rules.md](../../../rule/package-rules.md#a-package-compiles-the-gestures-of-its-home) says which package runs which list, and [builder.md](../../tool/builder/builder.md) describes the build that runs `warm_application`.

`evaluate_reachable_cells!` reads every reactive `Cell` that a printed output reaches, capped by `_WARMUP_WALK_MAX_DEPTH` and `_WARMUP_WALK_MAX_NODES`, so that a caller compiles the bodies of the cells and the closures of a printer, and not only the graph that holds them.

### `default_backend`

`default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend))` constructs a backend by reflection over the loaded `Backend` subtypes, with `compute_loaded_subtypes`, the subtype walk of the domain slice, which needs no `InteractiveUtils` (see [domain.md](../domain/domain.md)): it matches each name of `prefer`, in order, against a type's own name or its qualified name (`parentmodule(T)`, `.`, `nameof(T)`), and constructs the first one that is loaded. So a caller needs no dependency on a backend package, and no `:kind` key is coined for one. It raises an error, naming the backends that are loaded, only when none of `prefer` is. `run_application` calls it with no argument when `backend` is `nothing`.

## How it fits

The application slice depends on the kernel and on the assistant, collection, conversation, display, domain, fileformat, filesystem, gesturelog, natural, pane, primitive, projection, screen, serialization, shell, style, text, tooltip, undo and widget slices of `ProjecturedPlatform`; `PLATFORM_SLICE_EDGES` in [PlatformSuite.jl](../../../../test/platform/PlatformSuite.jl) has the row.

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
- Tests: `test/projectured/editor/ApplicationTest.jl`, `test_application()`. It covers the assistant pane and its declared API, the command line (`parse_application_arguments`, `run_application_command`), the warm-up, and the whole window: the first focus, a verb through the readers, every file format drawn, `Ctrl+S`, the menu bar and the toolbar, the evaluator opened from the toolbar, a noted object pasted into a form, and the tree of the folder.

## Limits

- A press on the Assistant button, once its tab has closed, opens a fresh `Assistant` through `make_application_assistant` with the backend, the model and the context of the window's own assistant: the conversation starts over at the greeting, because the window keeps no assistant of its own once its tab is gone.
- The menu bar has no Save, Reload, Command palette, Gesture help or clipboard items yet; see the Limits of [shell.md](../shell/shell.md).
- The tree of the Files tool opens collapsed by default, so a scenario that scrolls to a file three folders deep finds nothing drawn yet to scroll to. Two assertions of `test_application()` are marked `@test_broken` for this reason, in "the Files pane scrolls a tree taller than its pane".
