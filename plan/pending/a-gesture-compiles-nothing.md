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
- **D7** (the owner, 2026-10-27: "yes, I agree"): `ScriptedLlm` and its
  builders (`make_scripted_turn`, `make_scripted_think`, `make_scripted_say`,
  `make_scripted_run`) move from `example/kernel/LlmScripted.jl` into the slice
  of the model protocol (`source/kernel/llm/`), as a model that replays given
  rounds. The workload of the platform runs an assistant turn with it. The
  assistant turn costs 236 statements in projectured and 296 in omnet_ide. The
  comment that it lives in the example package "so no fake reaches a
  production build" goes. `ProjecturedKernelExample` stops including the file;
  its tests and tools take the name from the kernel. No file of
  `source/kernel/llm/` is sealed (checked 2026-10-27).
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

1. [ ] **The shape (D4).** `insertable` and the API table of
   `_refuse_declared_twice` stop their specialization for each type and each
   function. Find the other statements of the same shape in the traces.
   Expected: the start of projectured falls by about 115, and the start of
   omnet_ide by about 820.
2. [ ] **The gesture machinery of the platform (D2).**
   - `WorkloadBackend` takes gestures that name their target: a drawn text, a
     part of a document, a key, or a typed text. It finds the target in the
     screen that it read last.
   - `run_application_workload(files; gestures)` starts the application window
     as `run_application` does (`build_editor`, `start_application!`, the
     loop). It waits until each gesture ran and the window is quiet.
   - `ScriptedLlm` moves into `source/kernel/llm/` (D7), and the assistant
     turn of the list uses it.
   - A test in `ProjecturedPlatformTest` runs a list and asserts that each
     gesture found its target.
3. [ ] **The workloads of the platform and SDL (D3).**
   - The platform runs the window gestures of D3 over a `.txt` file and a
     `.pred` file.
   - SDL runs the same list on `SdlBackend` under the dummy driver, with the
     events through the event queue of SDL.
   - A fact for SDL: the dummy and the offscreen drivers give the focus to each
     new window. The main window then loses the focus, and the editor closes
     each popup. The workload drops the focus events, as a window manager does
     for a popup.
4. [ ] **The domain packages and the language server (D3).**
   `run_file_workload(name, text)` of the platform opens a file in the
   application window and runs the gestures of a file.
   - A domain package with a file type calls it with a file of its format,
     beside its natural rows: JSON, YAML, XML, Markdown, RST, Math, Julia, and
     Database (`.sql`).
   - A domain package with no file type opens a `.pred` file that holds one of
     its documents: Book, Chart, Formula, Graph, Pivot, Workflow, Research.
   - ProjecturedLanguageServer opens a `.c` file with no server.
5. [ ] **The app package, the guard and the rules (D9, D10).**
   - `warm_application` runs the list of the binary.
   - The guard `test_gestures_compile_little` goes into `ProjecturedTest`,
     beside `test_first_window_compiles_little`, and asserts the target.
   - The rules: `package-rules.md`, and `PackageGraphTest.jl` allows a
     `@compile_workload` in the entry file of each package that has gestures.
   - The text that still says "only in a leaf": `CONTRIBUTING.md:69`,
     `division-terminology.md:50`, `repl.md:5` and `:11`. Also `builder.md` and
     `application.md`, which describe `warm_application`.
6. [ ] **What still compiles at a click (D5).** After step 5, the guard shows
   what the images still do not hold: the recompiles that the app package does
   not cover, and the Base methods on our types that dynamic dispatch reaches
   (the 119 of `warm_application`). Fix each where it starts, with no cost on
   `read_intent`, `print_document` or another call for each node or event.

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
8. [ ] **OmnetIde, its app package and its guard.**
   - OmnetIde gets its own `@compile_workload`: the IDE window with its
     wrappers, and the gestures of D3.
   - `CampaignPrecompile.jl` and `IdePrecompile.jl` become its body, with no
     bare `catch` (D6).
   - The app workload runs the list of the binary.
   - The guard goes into `OmnetIdeTest`.

### Both

9. [ ] **The measurement.** Run the guards of both binaries, from source and
   built. With the owner's approval, on an idle machine, measure the costs: the
   build time of each package that got a workload, the image sizes, the time
   of the `using` line, and the first window. The owner decides with these
   numbers.

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
