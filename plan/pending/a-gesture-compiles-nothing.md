# A gesture compiles nothing

Status: pending. Written 2026-10-27. D1, D5, D7 and D8 are the owner's. The
other decisions are proposed.

Applies to projectured-julia and omnet-julia.

## The ask

The owner, 2026-10-27: "analyze the compiler workload for the various
projectured-julia and omnet-julia packages and come up with a plan to make the
projectured binary and the omnet_ide much more responsive by avoiding compiling
code when the user is clicking on menu items, toolbar buttons, explorer items,
context menus, opens various files, runs simulations, talks to the assistant,
etc." and "each compiler workload should go into their respective packages".

## What was measured (2026-10-27)

Two drivers opened each application in the environment that its launcher runs
(`build/app/projectured`, `build/app/omnet_ide`), with the package images that
the launcher builds. They used the SDL backend under the offscreen driver and
the real loop of the editor. Each gesture went into the event queue of SDL
(`SDL_PushEvent`), at a point found in what was drawn. `--trace-compile` and a
marker before and after each gesture gave the statements of each gesture.

These are counts, not times. A count does not change with the load of the
machine. A second pass of the same gestures compiled almost nothing
(projectured 1, omnet_ide 23), which confirms the method.

The **home** of a statement is the lowest loaded package whose dependency
closure holds every module in its signature. The image of that package can hold
the code.

### bin/projectured (projectured-julia main of 2026-10-27)

| Gesture | Statements | Recompiles |
|---|---:|---:|
| start to the first quiet frame | 569 | 21 |
| menu bar: open Help | 172 | 2 |
| menu: choose About | 219 | 0 |
| toolbar: Files | 398 | 0 |
| Files pane: click `a.json`, then Enter | 197 + 169 | 7 |
| open `.jl` / `.sql` / `.c` / `.rst` / `.math` / `.yaml` / `.xml` / `.pred` / `.txt` | 180 / 124 / 119 / 95 / 86 / 77 / 74 / 56 / 142 | 2 |
| right press on a tree row; choose "Open in a new tab" | 173 + 105 | 0 |
| text: click, type, Ctrl+S, Ctrl+Z | 58 + 60 + 45 + 29 | 0 |
| tab: switch, Ctrl+W | 10 + 29 | 0 |
| assistant: open, click the draft, type, send with one tool call | 16 + 120 + 33 + 236 | 0 |
| F1 / Ctrl+Shift+P | 257 / 53 | 0 |
| toolbar: Settings | 305 | 0 |
| **all 40 gestures** | **4305** | **32** |

- ProjecturedPlatform is the home of 2997 statements (70 %).
- When a file of a format opens, the domain package of that format is the home
  of most of its statements: `.sql` 109 SQL, `.rst` 93 RST, `.math` 79 Math,
  `.yaml` 72 YAML, `.xml` 61 XML, `.jl` 58 Julia, `.c` 56 LanguageServer.
- `.md` compiles 8, because `warm_application` opens a Markdown file.
- 115 of the 569 statements of the start have one shape:
  `setindex!(::Dict{Symbol,Tuple{Module,Any}}, ::Tuple{Module,typeof(f)}, ::Symbol)`,
  one for each function that an API declares (`_refuse_declared_twice`,
  [ToolSet.jl:110](../../source/kernel/tool/ToolSet.jl#L110)).
- `warm_application()` runs to its end. A fresh process that runs it again
  still compiles 119 statements. They are small Base methods on our types that
  code reaches through dynamic dispatch, for example
  `iterate(::Vector{TextDocument})` and `getindex(::Vector{Expr}, ::Int)`.

### bin/omnet_ide (omnet-julia main 5962eb170, after the fold of the campaign window)

| Gesture | Statements | Recompiles |
|---|---:|---:|
| start to the first frame | 1786 | 111 |
| View menu → Appearance | 1038 | 12 |
| toolbar: Files | 319 | 0 |
| explorer: projects, a project, a double press, Files | 629 | 7 |
| open 18 files | 2932 | 47 |
| right press → Sort | 253 | 5 |
| Runner: type a configuration, Run (4 tasks of a stub `opp_run`) | 511 | 5 |
| INI: click, type, Ctrl+S, Ctrl+Z | 399 | 5 |
| assistant: a prompt with one tool call | 296 | 1 |
| F1, F1, Ctrl+Shift+P, Escape | 278 | 14 |

- The 18 files: the study `.pred` 1257, `.ned` 349, `.jl` 201, `.sca` 176,
  `.md` 171, `.elog` 121, `.cc` 118, `.json` 115, `.ini` 113, `.rst` 112,
  `.yaml` 96, `.xml` 80, and six more under 30.
- The homes over all gestures: the projectured-julia packages 6991
  (ProjecturedPlatform 4767), the omnet-julia packages 1051 (OmnetLegacyFormat
  384, OmnetLegacySimulatorPresentation 264, OmnetLegacyResultPresentation 220,
  OmnetIde 108), Base 549.
- 647 statements of the start are `insertable(::Type{T})`, one for each
  document type (`get_insertion_candidates`,
  [Domain.jl:278](../../source/platform/domain/Domain.jl#L278)). 174 are the
  `setindex!` of the API table above.
- 97 of the 111 recompiles of the start are code of ProjecturedPlatform.
  `read_intent` is the function that is recompiled most (31).
- `OmnetIde.precompile_workload!` runs to its end in a plain process. The
  generated `OmnetIdeApp` runs it in its `@compile_workload`, also when
  `bin/omnet_ide` runs from source.

The drivers and the results are in `/var/tmp/gesture-compiles/`: the drivers
`projectured/gesture-driver.jl` and `omnet/drive.jl` (started by
`omnet/run.sh`), and the results `projectured/measure3/` and
`omnet/out/drive3/`.

## Why the gestures compile

1. **The workloads print, and they do not run the gestures.**
   - The workloads of the platform, SDL and data frames show a table.
   - The workloads of the domains build the natural rows and parse no file.
   - `warm_application` runs on the console backend, so SDL paints no window
     of the application.
   - The IDE workload reads F1 and Ctrl+Shift+P, and drops the operations.
   - No workload opens a menu, a context menu, a tool of the toolbar, a file
     of most formats, a run, or an assistant turn.
2. **A function specializes once for each type or function of a set.**
   `insertable` (647) and the API table (115 and 174).
3. **The load invalidates code that an image holds.** 32 recompiles in
   projectured and 207 in omnet_ide, most of them code of ProjecturedPlatform.
4. **A workload hides its faults.** `CampaignPrecompile.jl` and
   `IdePrecompile.jl` end in a bare `catch`. `warm_application` writes its
   fault into the build output, and the launchers hide that output. When a
   workload breaks, it stops compiling, and nothing shows it.

## Decisions

- **D1** (the owner, 2026-10-27): each compile workload goes into its own
  package. In omnet-julia this replaces the rule "a `@compile_workload` lives
  only in a leaf" (`documentation/rule/package-rules.md:39`, `:63` and `:252`)
  and its test (`test/package/PackageGraph.jl:100`). projectured-julia made the
  same change on 2026-10-08 for the first window.
- **D2**: a workload runs a gesture through the real loop of the editor. The
  backend gives the event. The frame reads it, evaluates the operation, drains
  what was posted, prints, and writes the output. A workload finds each target
  in what was drawn: a text, a part of a document, or a key. One gesture of
  each kind is enough, because each item of a menu walks the same chain. The
  guard (D9) presses each item.
- **D3**: a gesture goes into the workload of the home of most of its
  statements. From the counts:

  | Package | Its gestures |
  |---|---|
  | ProjecturedPlatform | the window: the menus and their items, the tools of the toolbar, the Files pane, the Explorer, the context menus, tabs, splits, text edits, save, undo, F1, the palette, Settings, Appearance, the assistant pane and a turn |
  | ProjecturedSDL | the same window through SDL: the event translation, the popup windows, the paint |
  | each domain package with a file type | open a file of its format from the Files pane, click in it, type, save, undo |
  | each domain package with no file type | open a `.pred` file that holds one of its documents |
  | ProjecturedLanguageServer | open a `.c` file with no server process |
  | OmnetLegacyFormat | open, edit and save a `.ned` file and an `.ini` file |
  | OmnetLegacyResultPresentation | open `.sca`, `.vec` and `.elog`; sort and scroll a table; a plot |
  | OmnetLegacySimulatorPresentation | the project page, the Runner form, Run (D8) |
  | OmnetIde | the IDE window with its wrappers, a study, the About page, a turn with the API of the IDE |
  | the generated app package | the list of the binary over every format (D10) |

- **D4**: a function that runs once for each type or each function of a set
  does not specialize on it. Use `@nospecialize`, a `Type` argument with no
  type parameter, or a value converted to the type of its field where it is
  made.
- **D5** (the owner, 2026-10-27: "recompiling is not such a big problem after
  all, as long as most of the methods get compiled eventually"): an
  invalidation costs a click only when no later image compiles the code again.
  The app package compiles it again in its build (D10). So the plan fixes an
  invalidation only when the guard still shows a recompile at a click after
  step 5. Such a fix uses the rules of `package-rules.md` (a concrete type where
  a value is made, an integration loads the packages below it first). It never
  puts `invokelatest` or `@max_methods` on `read_intent`, `print_document` or
  another call that runs for each node or each event: "those are called many
  many times, we should be careful to not make this slow" (the owner,
  2026-10-27). This holds for the binaries and the REPL leaves. A session of
  the released packages has no last package, and it recompiles at first use.
- **D6**: a workload body lets a fault through. A test of its package calls the
  body in a normal process and asserts that each gesture found its target. Only
  the `@compile_workload` site catches, with `@warn`, so that a failed workload
  never stops a package from loading.
- **D7** (the owner, 2026-10-27: "I'd put this into the ApplicationWorkload.jl
  and make a minimal interface that can be used by the omnet IDE to make it
  work"): the model of a workload turn lives in
  `source/platform/application/ApplicationWorkload.jl`.
  `make_workload_llm(code; answer)` makes it. Each turn of the model has a
  first round that thinks, says a line and asks `execute_julia_code` to run
  `code`, and a second round that says `answer`. The workload of the platform
  gives it to `run_application_workload` (keyword `llm`), and the workload of
  omnet_ide gives it to its own window (`run_omnet_ide` takes `llm`). The
  assistant turn costs 236 statements in projectured and 296 in omnet_ide.
  `ScriptedLlm` stays in `ProjecturedKernelExample` for the tests and the
  tools, and the kernel does not change. The rule `PAR-NO-TEST-DOUBLES-IN-MAIN`
  states this model as its one exception: only a compile workload makes one.
  An earlier form of D7, a move of `ScriptedLlm` into `source/kernel/llm/`,
  was dropped: it broke that rule for a public kernel name, and a model in the
  platform alone would have needed a second copy for omnet.
- **D8** (the owner, 2026-10-27: "can't we imitate starting a process from pure
  Julia?", and "yes" to the mechanism below): a workload imitates a process in
  Julia, so that a build starts no process. Run costs 281 statements. Each task that
  runs a process goes through one function, `start_process_task!`
  ([TaskExecution.jl:451](../../source/platform/task/TaskExecution.jl#L451)),
  which calls `run(pipeline(command; stdout, stderr); wait = false)`. After
  that call, the readers, `read_line`, `finish`, the stop and the task group
  use only the two streams and the process object (`exitcode`, `termsignal`,
  `getpid`, `kill`, `wait`). The mechanism, new in the task slice:
  - a scoped value that holds a function which imitates a command; when it is
    set, `start_process_task!` calls that function in place of `run`;
  - `ImitatedProcess`, which answers as a process does: the function writes
    its lines into the two streams on a task, and its return value is the exit
    code;
  - the workload of OmnetLegacySimulatorPresentation sets it around its
    gestures: the imitation of `opp_run` prints the status lines of Cmdenv,
    writes a `.sca` and a `.vec` file, and ends with 0. So the progress, the
    end of a run and the results that a run wrote also compile.

  The project of the workload still needs a file at the path of the executable,
  because a run checks `isfile` before it starts.
- **D9**: each binary gets a guard. A test drives the full list of gestures
  (each menu item, each tool of the toolbar, each format) in a fresh process of
  the app environment under `--trace-compile`, and asserts a bound for each
  gesture. A count does not change with the load of the machine, so the test is
  stable.
- **D10**: the workload of the generated app package runs the list of the
  binary over every format. Its image then holds the code that the packages
  loaded later invalidate in the images below it (rule 3 of D5).
- **D11**: a developer turns off a slow workload with the switch that
  PrecompileTools has (`precompile_workload = false` for that package in
  `LocalPreferences.toml`). There is no new switch.

## The target

In a fresh process of each app environment, counted by the guard: the start
compiles at most 50 statements, each gesture at most 10, and no gesture
recompiles. This is proposed. Today the start compiles 569 and 1786, and the
second pass of each gesture compiles 0 to 8.

## Steps

Each step is one or more commits in a worktree. Mark a step here when it lands.
Until the guards exist (steps 5 and 8), measure with the drivers in
`/var/tmp/gesture-compiles/`.

### projectured-julia

1. [x] **The shape (D4).** `insertable` and the API table of
   `_refuse_declared_twice` stop their specialization for each type and each
   function. Find the other statements of the same shape in the traces.
   Expected: the start of projectured falls by about 115, and the start of
   omnet_ide by about 820.

   Done on the branch `gesture-compiles`. Three generic methods compiled a copy
   for each type or each function:
   - `insertable` and `_zero_arg_constructible` take `@nospecialize(T::Type)`;
   - `is_view_state_field(T, name)` takes `@nospecialize(T::Type)` (the
     traces showed 54 copies in omnet_ide and 18 in projectured);
   - `_refuse_declared_twice` keeps the values in a `Dict{Symbol,Any}`, whose
     `setindex!` in Base does not specialize on the value.

   The other functions with a `Type{_}` argument in the traces
   (`get_theme_field_texts`, `make_pred_document`,
   `get_document_gesture_bindings_own`, `get_insertion_aliases`) have a method
   for each type. Each method compiles once, so a workload covers them.

   Measured in a fresh process of the test environment of the platform (580
   concrete document types, 116 candidates, 35 API entries), statements before
   and after:

   | Call | Before | After |
   |---|---:|---:|
   | insertion candidates | 297 (278 `insertable`) | 157 |
   | declare the editor API | 105 (81 `setindex!`) | 24 |
   | view state of 580 types | 581 | 2 |

   The 157 that remain are 141 zero-argument constructors, which
   `_zero_arg_constructible` calls as `T()` to test a type. Before, each
   compiled inside the copy of `insertable` for its type. A constructor is a
   method of its own type, so `@nospecialize` does not remove it.

   The cost is one more dynamic dispatch for each check in
   `is_view_state_field`: the call `get_view_state_fields(T)`. Its callers in
   walks pass `typeof(node)` of a node of unknown type, so they dispatch at run
   time already.

   Tests: `test_declared_api` 156, `test_document_macro` 129,
   `test_construct_oracle` 17, `test_insertion_choices` 23, `test_help_tree` 45,
   `test_pred_file` 45, `test_context_menu_window` 60, `test_explorer` 294; no
   fail, error or broken. The probe is `/var/tmp/gesture-compiles/shape/probe.jl`
   with `count.py`.
2. [x] **The gesture machinery of the platform (D2).**
   - `WorkloadBackend` takes gestures that name their target: a drawn text, a
     part of a document, a key, or a typed text. It finds the target in the
     screen that it read last.
   - `run_application_workload(files; gestures)` starts the application window
     as `run_application` does (`build_editor`, `start_application!`, the
     loop). It waits until each gesture ran and the window is quiet.
   - The model of a workload turn (D7), and the assistant turn of the list
     uses it.
   - A test in `ProjecturedPlatformTest` runs a list and asserts that each
     gesture found its target.

   As built (`source/platform/application/ApplicationWorkload.jl`):
   - The steps are `WorkloadClick(target; button)`, `WorkloadKey(key; ctrl,
     shift, alt)`, `WorkloadTyping(text)` and `WorkloadWait(target)`, under
     `WorkloadStep`. A target is `DrawnText(text; pick)` (a `String` matches a
     whole drawn text, a `Regex` a part; `pick` is `:first`, `:leftmost` or
     `:topmost`) or `DrawnPart(predicate)` (the drawing of the first view
     whose input passes the predicate, such as a tool of the toolbar). The
     word "gesture" stays out of the type names, because `Gesture` is the
     kernel type of `MouseClick` and `KeyChord`.
   - The backend does not find the targets. `run_application_workload` finds
     each target with a call on the task of the loop (`run_on_editor_task!`),
     between two frames, and gives the inputs with
     `send_workload_inputs!(backend, inputs)` in the display slice. The reason:
     step 3 gives the same steps to `SdlBackend`, which then needs only a
     method of `send_workload_inputs!`.
   - `WorkloadBackend` gives one queued input in each frame, as a hand does:
     a click is a move, a down and an up in three frames. A key gives its
     down, its character (Return and Tab, as SDL does) and its up.
   - The window is quiet when, for 0.25 s of looks, the last frame applied no
     input, no wake waits, no timer of the editor waits (`editor.timers`), and
     the backend holds no input. A look is an inbox call, and an inbox
     operation does not set `editor.operation`, so a look does not make the
     window busy. The timers matter: gesture tracking holds a click until its
     timer shows that no second click follows, and keys typed before that
     timer fires are lost. Only gesture tracking sets a timer, and each timer
     comes from an input and fires once, so the window does become quiet.
   - A call on the loop that the editor does not start in time, because a
     frame compiles a first gesture, counts as busy, not as a fault.
   - A click on a `DrawnPart` presses the middle of its drawing. The test
     found a defect there: a press on the draft of the assistant beside its
     text was read as "do nothing". A card is a solid surface (2026-10-08), and
     the text of the draft is only as wide as what is written. Fixed on the
     owner's word ("fix it and continue"): a plain left click that nothing
     inside a card uses reads the bindings of the card before the solid
     surface, and the card of the active typein binds it to the caret at the
     end of what is written (`test_draft_press`, and a test of the binding in
     `test_widget_card_fold`).
   - `run_application` and the workload build the window with one function,
     `_make_application_editor`. The workload reads no settings file and no
     appearance file, names no assistant backend (`:none`, with the `llm` of
     the caller), and starts no MCP server.
   - The workload runs with the fault barriers of the application, so that
     the image holds the code of the barriers (`make_inverse_operation`). At
     the end it throws an error that names each step whose target was not
     drawn in `timeout` seconds, the step before which the loop ended, and
     each fault that a barrier caught (D6).
   - A `ChildrenIoMap` builds its `child_iomaps` only when a reader asks, so
     no print computes it. The walk of a `DrawnPart` takes the children of a
     view from `get_child_iomaps`, as a reader does, and reads the other
     fields of a view only when their cell holds a value.
   - `WorkloadBackend` answers `shows_held_frames = false`: it shows no
     window, so a code unit runs on the thread of the loop, and the window
     gives no notice about the threads of a tool call.
   - In a fresh process, each first gesture makes a frame slower than a
     second, and the editor writes a warning for each (13 in the test). A
     precompile writes none: `_report_slow_frame!` skips them while
     `Base.generating_output()`.

   Done: the machinery, `make_workload_llm`, and their test
   (`test_application_workload`, 14 of 14, 75 s in a fresh process; the list
   runs a menu and its popup, a tool of the toolbar, a row of the Files pane
   with Enter, a click and typing in the opened text, Ctrl+S, Ctrl+Z, a tab,
   a context menu, F1, the palette and an assistant turn with a tool call).
   - `make_workload_llm` (D7) streams no `LlmToolInputDelta`, because no
     reader of the platform reads one; so it needs no JSON writer.
   - A fact for step 8: omnet_ide builds its own window (`run_omnet_ide` →
     `run_campaign_window`), so its workload needs the steps of an editor that
     it started. That step takes the loop of the steps out of
     `run_application_workload` into a function of an editor.
3. [x] **The workloads of the platform and SDL (D3).**
   - The platform runs the window gestures of D3 over a `.txt` file and a
     `.pred` file. The list includes a new tab with Ctrl+T and Insert, so that
     the image holds the constructors of the platform types, which the insertion
     list calls to test each type (step 1).
   - SDL runs the same list on `SdlBackend` under the dummy driver, with the
     events through the event queue of SDL.
   - A fact for SDL: the dummy and the offscreen drivers give the focus to each
     new window. The main window then loses the focus, and the editor closes
     each popup. The workload drops the focus events, as a window manager does
     for a popup.

   As built:
   - `run_window_workload(; backend)` in `ApplicationWorkload.jl` holds the
     list: Help › About, View › Split vertically, Help › Documents; the open
     of `a.txt` and of `b.pred` (a `CellVector` of two `PrimitiveString`s) from
     the Files pane, each with a click, a key, Ctrl+S and Ctrl+Z; a tab; the
     Explorer and its context menu; Ctrl+T, Insert and a typed name; F1 twice;
     the palette; each other tool of the toolbar (Evaluator, Selection,
     Appearance, Settings, Assistants, the four record tools); an assistant
     turn; Ctrl+W. `test_window_workload` passes, 3 min 22 s in a fresh
     process.
   - `run_application_workload` takes `backend`. The platform workload calls
     `__init__()` first, because the text rows that the open of `a.txt` needs
     are registered there, and a precompile runs the workload before it.
   - SDL: `send_workload_inputs!(::SdlBackend)` in
     `source/backend/sdl/SdlWorkload.jl` makes the SDL event of each input
     (motion, button, key with the code that `sdl_keysym_to_symbol` reads
     back, text input) and pushes it with `SDL_PushEvent`; it skips the
     `KeyPress` of Return and Tab, which SDL types from the key. It sets an
     event filter that drops the focus events; `run_sdl_window_workload`
     clears the filter at the end. `has_workload_inputs(::SdlBackend)` reads
     the inputs that the backend holds and the queue of SDL.

   Facts found on the way, and what they changed:
   - A build runs no `__init__`, also not the `__init__` of a submodule. 19
     slices of the platform register their rows there, so the first build
     showed the assistant and the Explorer as reflected structs, whose print
     did not end (the build hit its 1 h bound). `run_module_initializers!(root)`
     in `DisplayWorkload.jl` runs each `__init__` of a module tree;
     `run_natural_rows_workload` uses it too.
   - A bug of Julia (1.11.9, 1.12.7 and 1.13.1): inference merges `Union{}`
     and another type `D`, returned by one call, into a subtype of `D`, and
     folds `x isa` it to the answer for `D`. Five lines show it:
     `f(::Type{Int}) = Float64; f(::Type{String}) = Union{}; g(x, T::Type) =
     x isa f(T); g(1.0, String)` answers `true`. In a session with the
     platform alone, `_is_format_node` of `PredFile.jl` (text files have the
     domain `Union{}`) answered `true` for every document, so a `.pred` file
     saved nothing. The domain now passes `Base.inferencebarrier`. A session
     that loads one more format, as the test environment does, never showed
     it, so the build of the platform alone is its check.
   - The editor runs each call of `run_on_editor_task!` in a code unit. With
     `SdlBackend` the unit runs on a thread of its own while the loop holds its
     frames, and a held frame drops the pointer input that starts during the
     hold. So a step finds its inputs in the call and the workload sends them
     from its own task after the held frames end (`editor.code_unit` is
     `nothing` again). `WorkloadBackend` locks its queue for that. SDL drops
     each event of its queue when a filter is set, so the SDL send sets the
     focus filter once, and it waits 2 ms after a push, because SDL counts time
     in milliseconds and a held frame keeps only the pointer input from before
     its start.
   - A key with modifiers presses the key of each modifier before it and
     releases it after it: SDL keeps the modifiers of the last key event, and
     a Ctrl that is never released made each later click a Ctrl+click.
   - A display update of SDL is no input that a step waits for: the chart of
     the frame times draws a new picture in each frame, and the window was
     never quiet.
   - `start_application!` gives the notice about the thread of a tool call only
     outside a build, as the slow frames are reported only outside a build.

   Results (fresh processes, 2026-10-27): `test_window_workload` passes in
   1 min 54 s with the new platform image, and in 3 min 22 s before it held
   the list; `test_application_workload` in 23 s, before 70 s;
   `test_sdl_workload` passes 7 of 7 (the round trip of each event, the focus
   filter, the list on SDL) in 2 min 10 s. The build of `ProjecturedPlatform`
   alone takes 236 s with the workload and 19 s without it; the build of
   `ProjecturedSDL` takes 2 min 12 s and peaks at 7.8 GB. Both builds write no
   warning. Step 9 measures the costs on an idle machine.
4. [x] **The domain packages and the language server (D3).**
   `run_file_workload(name, text)` of the platform opens a file in the
   application window and runs the gestures of a file.
   - A domain package with a file type calls it with a file of its format,
     beside its natural rows: JSON, YAML, XML, Markdown, RST, Math, Julia, and
     Database (`.sql`).
   - A domain package with no file type opens a `.pred` file that holds one of
     its documents: Book, Chart, Formula, Graph, Pivot, Workflow, Research.
   - ProjecturedLanguageServer opens a `.c` file with no server.
   - Each of these workloads also opens the name buffer (Ctrl+T, Insert), so
     that its image holds the constructors of the types of its package.

   As built:
   - `make_workload_file(type)` in `DisplayWorkload.jl` answers the file of a
     workload, `(; name, text, shown)`. Each domain adds one method in the
     module file of its slice: for its file type (`JsonFile`, `YamlFile`,
     `XmlFile`, `MarkdownFile`, `RstFile`, `MathFile`, `JuliaFile`, `SqlFile`),
     or for a type of its documents, whose `.pred` text `print_pred_text`
     writes (`BookDocument`, `Chart`, `GraphGraph`, `WorkflowStep`,
     `ResearchQuestion`). The platform has the
     method of `TextFile`.
   - `run_file_workload(type)` in `ApplicationWorkload.jl` opens that file from
     the Files pane, clicks `shown`, types a key, saves, undoes, opens a new tab,
     types a key in the name buffer, cancels and closes the tab.
   - The entry file of each of the 13 packages keeps the line
     `@compile_workload run_natural_rows_workload(<Domain>Module)`, which
     `PackageGraphTest.jl` reads, and gets a second `@compile_workload` that
     calls `run_file_workload(<Domain>Module.<Type>)` in a `try` with `@warn`
     (D6). The first block runs each `__init__` of the domain, where it
     registers its file type.
   - The test of D6 is one test in `ProjecturedTest`, `test_file_workloads`,
     which loads every domain and runs each method of `make_workload_file`. The
     platform has `test_file_workload` for its text file. Step 5 runs the same
     list for the app package (D10) and the guard (D9).
   - ProjecturedFormula and ProjecturedPivot get no file workload in this
     step; each keeps its workload of natural rows. Formula: a sheet computes
     its values by an evaluation into `Module(:FormulaScratch)`, a new module
     under `Main`, and a build refuses an evaluation into a module that it
     closed, so the open of a sheet records a fault in a build (in a normal
     process it works). A workload of Formula needs a sheet that a build does
     not compute. Pivot: a `PivotTable` holds a `PivotCrossTable` in
     `cross_table`, which the `.pred` notation does not hold, so no `.pred`
     file can carry a pivot. Both are open for the owner.
   - ProjecturedLanguageServer gets no workload in this step. The open of a
     `.c` file starts `clangd` at the first work of its background cell, and
     `clangd` is installed on this machine, so a build would start a process.
     Its workload comes with the imitation of a process (D8) in step 7.
   - A fact for the owner: a build of a domain image with a window workload
     uses several GB, and `Pkg.precompile` builds several packages at once.
     The verification ran with `JULIA_NUM_PRECOMPILE_TASKS=3`.

   Results (2026-10-28): `test_file_workloads` passes 28 of 28 (14 types, the
   text file of the platform and 13 domains) in 2 min 39 s in the environment
   `environment/all`; the build of that environment with the new workloads took
   8.5 min and wrote no warning after Formula and Pivot left the list;
   `test_package_graph` passes 417 of 417, and the layering guards of the 13
   domains pass. Done with three domains open: Formula and Pivot (above) and
   the language server (step 7).
5. [x] **The app package, the guard and the rules (D9, D10).**
   - `warm_application` runs the list of the binary.
   - The guard `test_gestures_compile_little` goes into `ProjecturedTest`,
     beside `test_first_window_compiles_little`, and asserts the target.
   - The rules: `package-rules.md`, and `PackageGraphTest.jl` allows a
     `@compile_workload` in the entry file of each package that has gestures.
   - The text that still says "only in a leaf": `CONTRIBUTING.md:69`,
     `division-terminology.md:50`, `repl.md:5` and `:11`. Also `builder.md` and
     `application.md`, which describe `warm_application`.

   As built:
   - `warm_application()` moved into `ApplicationWorkload.jl`. It runs
     `run_window_workload()` and then `run_file_workload` for each type of
     `collect_workload_file_types()` (new, in `DisplayWorkload.jl`: the types
     that have a method of `make_workload_file`, sorted). It answers `nothing`
     and lets a fault through (D6). The builder writes the catch: the workload
     of `projectured` is `try ProjecturedPlatform.warm_application() catch
     exception @warn … end`, an expression with no line node, so that no path
     of the checkout goes into the package. The old body (a console backend, a
     script of events, `_find_drawn_text_point`) is gone;
     `evaluate_reachable_cells!` stays, because `example/projectured/FileEditor.jl`
     uses it. Its test in `ApplicationTest.jl` is gone too: the two lists have
     their own tests, and the guard builds the package that runs them.
   - The list runs on `WorkloadBackend`, not on the first backend of the binary.
     An `SdlBackend` in a build needs the dummy driver and the focus filter of
     `run_sdl_window_workload`, and the platform names no backend. If the guard
     shows recompiles in the SDL code at a click, step 6 adds the SDL list to
     the workload of the binary. (My decision, for the owner to see.)
   - The guard needs a mark between two steps. The method that each kind of
     step had, `_find_workload_inputs(editor, step)`, is public now as
     `find_workload_inputs`, and `WorkloadStep` says that another kind of step
     is a subtype with a method of it. The drive of the guard defines a step
     that marks the trace. No other mechanism is new.
   - The guard `test_gestures_compile_little` (`test/projectured/GestureCompileTest.jl`,
     in `test_integration` after the first window):
     1. A process of the active environment writes the package of the binary
        with `build_projectured_executable(; context, compile = false)` into a
        temporary folder; the test gives it the manifest of the active
        environment with absolute paths, as the first-window test does. So the
        binary loads the images that the environment built, and only its own
        image builds.
     2. A fresh process builds that image (`using ProjecturedApp`), which runs
        `warm_application`; the build must write no warning.
     3. A fresh process with `--threads=auto,2 --trace-compile` and the
        offscreen SDL driver runs `run_application_workload` on `SdlBackend`
        with the full list: each item of each menu but File › Exit (12), each
        tool of the toolbar (13), the assistant turn, the Explorer and its
        context menu, the name buffer, F1, the palette, and the open and edit
        of a file of each type of `collect_workload_file_types()`, each file
        named after its type. A mark before each gesture splits the trace.
     4. It asserts the target: the start at most 50 statements, each gesture
        at most 10, no recompile.
   - `PackageGraphTest.jl`: a `@compile_workload` may also live in the entry
     file of a package whose slice defines `make_workload_file`, and such a
     package must call `run_file_workload(<Module>.<Type>)` there (a new
     test set). `package-rules.md` has the section "A package compiles the
     gestures of its home", with the table of D3, the form of the entry file,
     D6, the list of the binary and D11.
   - The texts: `CONTRIBUTING.md`, `division-terminology.md`,
     `system-anatomy.md`, `repl.md`, `builder.md`, `console.md`, and
     `application.md`, which now describes the workload of the window.

   Tests (2026-10-28): `test_package_graph` 418 of 418, `test_naming`,
   `test_build_executable` 268 of 268, `test_application_workload` 14 of 14,
   `test_file_workload` 3 of 3. The images of `environment/all` built in 11 min,
   peak 11.5 GB, with no warning.

   The guard, first run (2026-10-28, a busy machine; the counts do not depend
   on the load): 6 min 24 s, peak 5.6 GB. The image of the binary built in
   3 min 28 s and wrote no warning, and each of the 166 gestures found its
   target. Compared with the measurement of 2026-10-27 on main:

   | | Before (40 gestures) | After (166 gestures) |
   |---|---:|---:|
   | the start, statements (recompiles) | 569 (21) | 159 (53) |
   | the gestures, statements | 4305 | 453 |
   | the gestures, recompiles | 32 | 37 |
   | gestures over 10 statements | most | 14 |

   - The open of a file of each format compiles 0 to 5 statements; before,
     56 to 197.
   - Over the bound of 10: Help › Projections 37, the assistant turn 35, Help ›
     Gestures 30, the tool Frame times 25, the Explorer again 23, Open in a new
     tab 19, the typed name 18, the tool Evaluator 17, View › Split
     horizontally 16, the first menu 15, Ctrl+S of the Book file 14, the tool
     Frame statistics 13, the tool Files 11, Help › Documents 11.
   - The recompiles are spread: 1 to 5 in 22 gestures, and 53 in the start.
   - The three assertions of the target are `@test_broken` until step 6. The
     log is `/var/tmp/gesture-compiles/step5/guard-2026-10-28.log`.
6. [x] **What still compiles at a click (D5).** After step 5, the guard shows
   what the images still do not hold: the recompiles that the app package does
   not cover, and the Base methods on our types that dynamic dispatch reaches
   (the 119 of `warm_application`). Fix each where it starts, with no cost on
   `read_intent`, `print_document` or another call for each node or event.

   Found in the trace of the guard (`/var/tmp/gesture-compiles/step6/`:
   `run-guard.jl` runs the three processes of the guard into a folder that
   stays, `analyze-guard.py` gives the home of each statement):
   - The recompiles were SDL code: the backend protocol on `SdlBackend`, the
     paint, the fault barrier, and `read_intent` for `DisplayUpdate`,
     `WindowLeave` and `MouseDwell`, events that only SDL gives. The image of
     SDL compiles them, a package loaded later makes them invalid, and the
     workload of the binary ran only on `WorkloadBackend`.
   - D2 was wrong that one item of each menu is enough. Each item and each
     tool opens a document of its own type (`ProjectionList`, `Settings`, …),
     and the printers compile for each type: Help › Projections compiled 37.
   - The order matters: the name buffer and F1 walk the open tabs and compile
     a method for each kind of tab (`unwrap_cell`, `is_pane_search_step`), so
     they must come after the tools.
   - The walk that finds a `DrawnPart` compiled a copy for each type of the
     window; that is the workload, not the gesture.
   - 28 statements of the start were the drive building its list.

   Fixed:
   - The workload of the binary also runs the window list on SDL:
     `PROJECTURED_BACKEND_WORKLOADS` in the builder names
     `ProjecturedSDL.run_sdl_window_workload()` (now exported), and the
     generated package runs each list in its own `try`.
   - `run_window_workload` presses each item of each menu but File › Exit and
     each tool, and then the name buffer, F1 and the palette. The items of Help
     come first (the warning below).
   - The walks of the workload take `@nospecialize` arguments.
   - The drive of the guard marks the start after it builds its list.
   - A defect that the longer list found: Help › Gestures with the Explorer
     focused faulted, `shift_event_position(::CollectIntents, …)`. The tree
     reader shifts each event it gives to its rows, also the query of the
     gesture help. `shift_event_position` now has the fallback that
     `map_event_position` has: a value that is no event comes back unchanged.
     `test_window_workload` covers it, because its list presses Help ›
     Gestures with the Explorer focused.
   - The error of a workload names the stack of a fault.

   Results (fresh processes, 2026-10-28):

   | | Step 5 | Step 6 |
   |---|---:|---:|
   | the start, statements (recompiles) | 159 (53) | 75 (1) |
   | 166 gestures, statements | 453 | 241 |
   | 166 gestures, recompiles | 37 | 3 |
   | gestures over 10 statements | 14 | 4 |

   The build of `ProjecturedPlatform` takes 260 s and of `ProjecturedSDL` 81 s;
   the image of the binary builds with no warning.

   What remains, and why it stays:
   - The start (75): 4 statements of the drive; about 40 small Base methods on
     Base types (`length(::Vector{Float64})`, `+` of four `Int`s), which a
     dynamic call reaches and which no package image keeps; the held frames of
     SDL (about 20), which a build never runs, because a build has one thread;
     and the notice about the threads of a tool call.
   - The assistant turn (25): the success path of a tool call. The kernel
     evaluates model code in `Module(:ToolScratch)`
     ([CodeExecution.jl](../../source/kernel/tool/CodeExecution.jl)), and a
     build refuses an evaluation into a module that it closed, so in each build
     the tool call fails and the scripted model answers anyway. It is the fact
     of Formula (step 4).
   - Help › Gestures over a Settings tab (19): the gesture help collects the
     bindings of the focused tab, and the split bindings duplicate that tab,
     which a Settings tab refuses with the warning "The pane has no
     duplicate". A defect of the gesture help, outside this plan.
   - Frame times (13): the chart draws lines only when frames were measured.
   - The first Ctrl+S (14): the report of the file watch comes after the quiet
     window of a workload ends.
   - The three assertions of the target stay `@test_broken`.

   Tests: `test_gestures_compile_little` 2 pass and 3 broken (the image of the
   binary builds in 4 min 47 s with no warning; 75, 241 and 3 as above),
   `test_window_workload`, `test_application_workload` 14 of 14,
   `test_sdl_workload` 7 of 7, `test_build_executable` 269 of 269,
   `test_gesture_help` 47 of 47, `test_package_graph` 418 of 418, `test_naming`.

### omnet-julia

7. [ ] **The rule and the legacy packages (D1, D3, D8).**
   - `package-rules.md` and `PackageGraph.jl` take the rule of
     projectured-julia.
   - OmnetLegacyFormat, OmnetLegacyResultPresentation and
     OmnetLegacySimulatorPresentation get their workloads, through
     `run_file_workload` and `run_application_workload`.
   - The imitation of a process (D8) goes into the task slice of
     ProjecturedPlatform first, in a commit of projectured-julia, with a test
     that runs a task group on it.

   As built (2026-10-28):
   - projectured-julia (`5d58e3462`): `source/platform/task/ImitatedProcess.jl`.
     Inside `run_with_process_imitation(f, imitation)` (a private scoped value,
     so a task that `f` starts imitates too), `start_process_task!` calls
     `imitation(command, output, error_output)` on a task of its own in place of
     `run`. `ImitatedProcess` answers `wait`, `process_running`,
     `process_exited`, `process_signaled`, `success`, `kill`, `exitcode` and
     `termsignal`; it has no identifier, so the sampler skips it; a stop
     records the signal, because a function runs to its end. An exception of
     the imitation goes into the error stream and ends it with the code 1.
     `test_task_group` runs five probes, an imitation that throws, and a stop.
   - projectured-julia: `run_file_workload` gives a file of a type that a person
     does not edit (`is_editable_file_type`) a click and no key, save or undo,
     because a result file is read-only.
   - omnet-julia (worktree `omnet-julia-gesture-compiles`, branch
     `gesture-compiles`): `make_workload_file` for `NedFile` (`a.ned`),
     `IniFile` (`a.ini`), `LegacyResultFile` (`a.sca`) and
     `LegacyEventLogFile` (`a.elog`); the entry files of `OmnetLegacyFormat` and
     `OmnetLegacyResultPresentation` run them in a `@compile_workload` after
     `run_module_initializers!`, and name `PrecompileTools`;
     `test_legacy_file_workloads` in `OmnetLegacyTest` runs the four.
   - omnet-julia rule: `package-rules.md` (the list of the rules, the section
     "A package compiles the gestures of its home", rule 4), `CLAUDE.md` and
     `engine-comparison-guide.md`. `PackageGraph.jl` allows a
     `@compile_workload` in the entry file of a package that calls
     `run_file_workload`, and asserts that each type with a method of
     `make_workload_file` under `source/` is opened by one.
   - The omnet side is tested in a joined environment,
     `/var/tmp/gesture-compiles/omnet-env`: the environment of omnet-julia with
     each path sent to the worktree of its repository, resolved offline.

   Facts that change the plan:
   - A `.vec` file opens as `LegacyResultFile`, the type of a `.sca` file, and
     `make_workload_file` gives one file for each type; the workload opens the
     `.sca` file only.
   - The language server starts `clangd` with `open(pipeline(…))`, a two-way
     pipe, not as a task, so D8 does not cover it; its workload stays open.
   - The Runner and Run of `OmnetLegacySimulatorPresentation` live in a window
     that `build_simulation_window` builds, so their workload needs the step
     loop for an editor that the caller starts (planned for step 8), and a
     project whose configurations are listed with no process: the discovery
     runs the executable with `-a` outside `start_process_task!`.

   Results (2026-10-28):
   - The projectured branch is rebased onto main (`ec35aadca`, 37 commits: the
     three pane verbs, `open_page!`), because omnet main uses `show_pane!`. One
     conflict: two imports of `MathModule.jl`, both kept. After the rebase:
     `test_window_workload`, `test_application_workload` 14 of 14,
     `test_file_workload` 3 of 3, `test_task_group` 84 of 84,
     `test_sdl_workload` 7 of 7, `test_file_workloads` 29 of 29,
     `test_package_graph` 418 of 418, `test_naming`. The build of the REPL leaf
     warns that 10.1 % of its recorded statements no longer resolve; 3 of the
     1592 name code that this branch changed.
   - omnet-julia (`ec99edf12`): `OmnetLegacyFormat` builds in 45 s and
     `OmnetLegacyResultPresentation` in 49 s, with no warning;
     `test_legacy_file_workloads` 5 of 5, `test_ned` 79 of 79, `test_ini` 39 of
     39, the naming law of omnet. `test_package_graph` 191 of 192: the one
     failure, `OmnetBench` depends on `OmnetSimulatorExample`, is on main too,
     as is the failure of the spelling check (`build_omnetpp!`). The old leaf
     check skipped a folder `package/repl`, which does not exist, so it named
     `OmnetRepl.jl` on main as well; the test now skips each package of
     `_LEAVES`.
   - The first sample of the `.elog` file waited for `host`, which the sequence
     chart does not draw; it draws the axis `Net`. The wait took 300 s for each
     of two steps, and the build of the package 642 s.
   - Not done: the workload of `OmnetLegacySimulatorPresentation` (the Runner
     and Run, above). It moves into step 8 (the owner, 2026-10-28: "yes, move
     to step 8").
8. [x] **OmnetIde, its app package and its guard.**
   - OmnetIde gets its own `@compile_workload`: the IDE window with its
     wrappers, and the gestures of D3.
   - `CampaignPrecompile.jl` and `IdePrecompile.jl` become its body, with no
     bare `catch` (D6).
   - The app workload runs the list of the binary.
   - The guard goes into `OmnetIdeTest`.

   The design:
   - projectured-julia: `run_workload_steps!(editor, steps; timeout)` gives
     the steps to an editor that the caller started with `wait = false`,
     stops its loop and throws the problems. `run_application_workload` calls
     it. `run_sdl_window_workload(run_workload = run_window_workload)` runs
     any window workload on SDL.
   - omnet-julia: `source/ide/IdeWorkload.jl` replaces the two files.
     `run_ide_window_workload(; backend, file_types)` writes a stub project
     (INI, NED, results, the study of `IdePrecompile.jl` saved as a folder,
     a stub executable), opens `run_omnet_ide` on it with a workload model,
     and gives the steps inside `run_with_process_imitation`: each menu
     item, each tool, the Explorer, the Runner form and Run, the results as
     a table and a plot, the study, Help › About, an assistant turn that
     calls an IDE verb, F1 and the palette, and a file of each of
     `file_types`. `warm_omnet_ide()` runs it over every file type.
   - The Runner and Run go into the workload of OmnetIde, because the
     window projection (`build_campaign_projection`) lives there.
   - The discovery (`-a`, `rundetails`) still runs the stub executable with
     `run`, as the workload on main does. Only `start_process_task!` is
     imitated: the build and the run.

   Facts that change the design:
   - `run_omnet_ide` takes an `assistant` document, so the workload gives the
     model in it (`Assistant(; llm = make_workload_llm(…))`). The keywords of
     `run_omnet_ide` do not change.
   - The window of the IDE has the menus of the platform (File: New tab,
     Close tab, Exit; View and Help with five items each) and the same 13
     tools, so the list is the list of the platform window.
   - `_result_code` of omnet took only a `Base.Process`, so each imitated
     run ended in a `MethodError`. It now takes an `ImitatedProcess` too.
   - After Run, the left pane shows the group of tasks. A click on the row
     Results of the Explorer does not open its page, so the list has no
     `.sca` or `.vec` in the Explorer. The study holds a result table and a
     result plot, and `warm_omnet_ide` opens a `.sca` file from Files.
   - Two faults of the product, outside this plan, which the list goes
     around:
     - A result view in a `.pred` file reads under the folder of the
       process, because a `.pred` file does not store its `root`. The
       workload opens the window in its project folder, as `omnet_ide`
       does by default.
     - After a save of a `.pred` file that holds a formula, the file watch
       reads the file again on its own task, and the formula computes there:
       the cell check of the kernel records a `ForeignCellWriteException`.
   - The study of `IdePrecompile.jl` held a formula sheet. A build refuses the
     evaluation of a formula (the closed module `FormulaScratch`, the fact of
     Formula in step 4), so the old workload failed at its first line in each
     build, and its bare `catch` hid it. The study of the workload holds no
     formula, so the workload also saves it.
   - A window with no size takes the size of the display of its backend, and
     the SDL dummy display is narrow: the assistant pane covered the page of
     the Explorer, and the Runner was not drawn. The workload opens the window
     at 1280 × 800, as the application workload of the platform does.
   - The test environment of omnet-julia does not hold `ProjecturedACP` and
     `ProjecturedMCP`, so the guard builds its binary with `assistant =
     false`. The workload gives the window its own model.

   Results (2026-10-28, in the joined environment):
   - The image of `OmnetIde` builds in 130 s with its workload, peak 5.0 GB,
     with no warning. The image of the binary of the guard builds in 3 min
     33 s with no warning; it runs `warm_omnet_ide()` over 16 file types and
     the same window on SDL.
   - The guard, `test_ide_gestures_compile_little`: 202 gestures, each finds
     its target. Compared with the measurement of 2026-10-27 on omnet main:

     | | Before (about 40 gestures) | After (202 gestures) |
     |---|---:|---:|
     | the start, statements (recompiles) | 1786 (111) | 90 (1) |
     | the gestures, statements | about 6655 | 248 |
     | the gestures, recompiles | about 97 | 1 |
     | gestures over 10 statements | 10 | 8 |

     145 gestures compile nothing. Over 10: Run (31), Return on `study.pred`
     (22), the Runner (18), Return in the assistant draft (15), Help ›
     Documents (14), Ctrl+S on the study (13), a tool (12), a click in the
     `.sca` file (11). The three bounds stay `@test_broken`.
   - Tests: omnet-julia `test_ide_window_workload` 1 of 1,
     `test_result_verbs` 68 of 68, `test_package_graph` 191 of 192 (the
     failure of main, `OmnetBench`), the naming law; projectured-julia
     `test_window_workload`, `test_application_workload` 14 of 14,
     `test_sdl_workload` 7 of 7, `test_naming`. Not run: `test_build` of
     omnet-julia, whose new assertions name the two calls that the builder
     wrote into the guard package, and the REPL leaf of omnet-julia, whose
     `:live` workload now calls `run_ide_window_workload`.

### Both

9. [ ] **The measurement.** Run the guards of both binaries, from source and
   built. With the owner's approval, on an idle machine, measure the costs: the
   build time of each package that got a workload, the image sizes, the time
   of the `using` line, and the first window. The owner decides with these
   numbers.

   The owner approved it on 2026-10-28 ("yes, do it"). The procedure, for main
   (projectured `1a4f8a3c5`, omnet `9227976a2`) and for the two branches, one
   job at a time, on the idle machine:
   - M1, the build of the images: a scratch depot whose `compiled` folder
     holds only the images of the packages from outside the two
     repositories, so that only the packages of the two repositories build.
     `Pkg.precompile(timing = true)` of the omnet environment `all` (it holds
     the packages of both repositories), then of the package of each binary.
     Recorded: the time of each package with a workload, the wall time, the
     peak memory, and the size of each image.
   - M2, the `using` line: five fresh processes each for `using Projectured`
     (the session of the README), the package of `projectured` and the
     package of `omnet_ide`; the median.
   - M3, the first window: the time from the start of the process to the
     first frame of the window of each binary package, five runs, the median.
   - M4, the guards from source: both guards on the branches.
   - M5, the built binaries: the build of both binaries, on main and on the
     branches: the build time and the size of the bundle; on the branches,
     the drive of each guard with the system image of the binary.
   - The package of `projectured` builds in the environment `all` of
     projectured-julia, which holds its model adapters. The package of
     `omnet_ide` builds with no model adapter (`assistant = false`), as its
     guard does.

## Hazards

- A workload that leaves a task, a timer, a file watch or a process open makes
  the precompile wait without end, and the launchers hide it. Before a landing,
  compile the real apps (`Pkg.precompile(["OmnetIdeApp"])`, and the projectured
  app) under a time bound.
- The workload of the platform runs at each change of the platform. A developer
  who changes the platform pays for it at the next start of `jp`. D11 turns it
  off.
- A larger image takes longer to load. The first-window workloads made the
  `using` line grow from 1.46 s to 1.87 s (2026-10-08). Step 9 measures it
  again.

## Not in this plan

The statement replay of the REPL leaves (`:recorded`) and the 39 statement
files; the HTTP and JSON code of the real model backends, which a scripted
model skips; the start of an ACP agent; a fault seen once in omnet_ide: after
the open of a `.sql` file fails, the mouse does nothing.
